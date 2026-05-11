defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  Thin GitHub REST client for the GitHub tracker adapter.

  Maps Symphony's "state" abstraction onto GitHub's open/closed + labels model:

  * An open issue's `state` is the value of its first label whose name matches one
    of the configured `active_states`. Open issues with no matching status label
    default to the first entry in `active_states` (conventionally "Todo").
  * A closed issue's `state` defaults to the first entry in `terminal_states`
    ("Done" by convention). Closed issues with `state_reason: "not_planned"`
    default to "Cancelled" if that's in `terminal_states`, otherwise the first
    terminal state.

  When `update_issue_state/2` is called with a terminal state the issue is
  closed (with `state_reason` set from the state name). Otherwise the active
  state label is rotated: any existing status label is removed and the target
  label is added.
  """

  require Logger
  alias SymphonyElixir.{Config, Linear.Issue}

  @per_page 100
  @max_error_body_log_bytes 1_000

  # Public API matching SymphonyElixir.Tracker callbacks ------------------

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    with {:ok, tracker} <- require_tracker_config() do
      active_set = state_set(tracker.active_states)
      assignee = normalize_assignee(tracker.assignee)

      with {:ok, issues} <- list_repo_issues(tracker, "open") do
        filtered =
          issues
          |> Enum.map(&assign_assignee_flag(&1, assignee))
          |> Enum.filter(&MapSet.member?(active_set, &1.state))

        {:ok, filtered}
      end
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized = state_names |> Enum.map(&to_string/1) |> Enum.uniq()

    if normalized == [] do
      {:ok, []}
    else
      with {:ok, tracker} <- require_tracker_config() do
        terminal_set = state_set(tracker.terminal_states)
        any_terminal? = Enum.any?(normalized, &MapSet.member?(terminal_set, &1))
        github_state = if any_terminal?, do: "all", else: "open"
        want = MapSet.new(normalized)
        assignee = normalize_assignee(tracker.assignee)

        with {:ok, issues} <- list_repo_issues(tracker, github_state) do
          filtered =
            issues
            |> Enum.map(&assign_assignee_flag(&1, assignee))
            |> Enum.filter(&MapSet.member?(want, &1.state))

          {:ok, filtered}
        end
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = issue_ids |> Enum.uniq() |> Enum.reject(&(&1 in [nil, ""]))

    if ids == [] do
      {:ok, []}
    else
      with {:ok, tracker} <- require_tracker_config() do
        assignee = normalize_assignee(tracker.assignee)

        result =
          Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
            case get_issue(tracker, id) do
              {:ok, issue} ->
                {:cont, {:ok, [assign_assignee_flag(issue, assignee) | acc]}}

              {:error, :not_found} ->
                {:cont, {:ok, acc}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)

        case result do
          {:ok, acc} -> {:ok, Enum.reverse(acc)}
          err -> err
        end
      end
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, tracker} <- require_tracker_config() do
      url = issue_url(tracker, issue_id) <> "/comments"

      case request(:post, url, tracker, json: %{"body" => body}) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status, body: body_resp}} ->
          Logger.error("GitHub create_comment failed status=#{status} body=#{inspect_short(body_resp)}")
          {:error, {:github_api_status, status}}

        {:error, reason} ->
          Logger.error("GitHub create_comment request failed: #{inspect(reason)}")
          {:error, {:github_api_request, reason}}
      end
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    with {:ok, tracker} <- require_tracker_config() do
      terminal_set = state_set(tracker.terminal_states)

      if MapSet.member?(terminal_set, state_name) do
        state_reason =
          if String.downcase(state_name) in ["cancelled", "canceled"],
            do: "not_planned",
            else: "completed"

        patch_issue(tracker, issue_id, %{"state" => "closed", "state_reason" => state_reason})
      else
        with {:ok, raw_payload} <- get_issue_raw(tracker, issue_id) do
          managed_lower = union_states(tracker)

          other_labels =
            raw_payload
            |> raw_label_names()
            |> Enum.reject(&MapSet.member?(managed_lower, String.downcase(&1)))

          new_labels = Enum.uniq([state_name | other_labels])
          # If the issue is closed, also reopen it.
          base = %{"labels" => new_labels}

          patch_body =
            case raw_payload["state"] do
              "closed" -> Map.put(base, "state", "open")
              _ -> base
            end

          patch_issue(tracker, issue_id, patch_body)
        end
      end
    end
  end

  # Private --------------------------------------------------------------

  defp require_tracker_config do
    tracker = Config.settings!().tracker

    cond do
      not is_binary(tracker.api_key) ->
        {:error, :missing_github_token}

      not is_binary(tracker.project_slug) ->
        {:error, :missing_github_repo}

      not String.contains?(tracker.project_slug, "/") ->
        {:error, :invalid_github_repo_format}

      true ->
        {:ok, tracker}
    end
  end

  defp list_repo_issues(tracker, github_state) do
    list_repo_issues_page(tracker, github_state, 1, [])
  end

  defp list_repo_issues_page(tracker, github_state, page, acc) do
    url = repo_url(tracker) <> "/issues"

    params = [
      {"state", github_state},
      {"per_page", Integer.to_string(@per_page)},
      {"page", Integer.to_string(page)}
    ]

    case request(:get, url, tracker, params: params) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        # GitHub returns PRs alongside issues — filter PRs out (they have a "pull_request" key)
        issues_only = Enum.reject(body, &Map.has_key?(&1, "pull_request"))
        normalized = Enum.map(issues_only, &normalize_issue(&1, tracker))

        if length(body) < @per_page do
          {:ok, Enum.reverse(acc) ++ normalized}
        else
          list_repo_issues_page(tracker, github_state, page + 1, Enum.reverse(normalized) ++ acc)
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("GitHub list_repo_issues failed status=#{status} body=#{inspect_short(body)}")
        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub list_repo_issues request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  defp get_issue(tracker, issue_id) do
    with {:ok, raw} <- get_issue_raw(tracker, issue_id) do
      {:ok, normalize_issue(raw, tracker)}
    end
  end

  defp get_issue_raw(tracker, issue_id) do
    url = issue_url(tracker, issue_id)

    case request(:get, url, tracker) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.error("GitHub get_issue failed status=#{status} body=#{inspect_short(body)}")
        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub get_issue request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  defp patch_issue(tracker, issue_id, body) when is_map(body) do
    url = issue_url(tracker, issue_id)

    case request(:patch, url, tracker, json: body) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("GitHub patch_issue failed status=#{status} body=#{inspect_short(resp_body)}")
        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub patch_issue request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  defp request(method, url, tracker, opts \\ []) do
    base_opts = [
      method: method,
      url: url,
      headers: github_headers(tracker),
      connect_options: [timeout: 30_000]
    ]

    Req.request(Keyword.merge(base_opts, opts))
  end

  defp github_headers(tracker) do
    [
      {"Authorization", "Bearer " <> tracker.api_key},
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"},
      {"User-Agent", "Symphony-Elixir"}
    ]
  end

  defp repo_url(tracker) do
    endpoint =
      (tracker.endpoint || "https://api.github.com")
      |> String.trim_trailing("/")

    endpoint <> "/repos/" <> tracker.project_slug
  end

  defp issue_url(tracker, issue_id), do: repo_url(tracker) <> "/issues/" <> to_string(issue_id)

  defp normalize_issue(payload, tracker) when is_map(payload) do
    number = payload["number"]
    title = payload["title"]
    state = determine_state(payload, tracker)

    %Issue{
      id: to_string(number),
      identifier: "GH-#{number}",
      title: title,
      description: payload["body"],
      priority: nil,
      state: state,
      branch_name: build_branch_name(number, title),
      url: payload["html_url"],
      assignee_id: get_in(payload, ["assignee", "login"]),
      blocked_by: [],
      labels: extract_labels(payload),
      assigned_to_worker: true,
      created_at: parse_datetime(payload["created_at"]),
      updated_at: parse_datetime(payload["updated_at"])
    }
  end

  defp determine_state(payload, tracker) do
    case payload["state"] do
      "closed" ->
        case payload["state_reason"] do
          "not_planned" -> pick_state(tracker.terminal_states, "Cancelled")
          _ -> pick_state(tracker.terminal_states, "Done")
        end

      _ ->
        active_states = Enum.map(tracker.active_states, &to_string/1)
        active_lower = Enum.map(active_states, &String.downcase/1)
        label_names = raw_label_names(payload)

        match =
          Enum.find(label_names, fn label ->
            String.downcase(label) in active_lower
          end)

        case match do
          nil ->
            List.first(active_states) || "Todo"

          name ->
            idx = Enum.find_index(active_lower, &(&1 == String.downcase(name)))
            Enum.at(active_states, idx, name)
        end
    end
  end

  defp pick_state(states, preferred) when is_list(states) do
    preferred_lower = String.downcase(preferred)

    states
    |> Enum.map(&to_string/1)
    |> Enum.find(fn s -> String.downcase(s) == preferred_lower end)
    |> case do
      nil -> List.first(Enum.map(states, &to_string/1)) || preferred
      found -> found
    end
  end

  defp raw_label_names(%{"labels" => labels}) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp raw_label_names(_), do: []

  defp extract_labels(payload) do
    payload
    |> raw_label_names()
    |> Enum.map(&String.downcase/1)
  end

  defp build_branch_name(number, title) do
    slug =
      (title || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 40)

    if slug == "" do
      "gh-#{number}"
    else
      "gh-#{number}-#{slug}"
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp state_set(states) when is_list(states) do
    states
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp union_states(tracker) do
    (Enum.map(tracker.active_states, &to_string/1) ++
       Enum.map(tracker.terminal_states, &to_string/1))
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end

  defp assign_assignee_flag(%Issue{assignee_id: assignee_id} = issue, configured_assignee) do
    matches? =
      cond do
        is_nil(configured_assignee) ->
          true

        is_nil(assignee_id) ->
          false

        true ->
          String.downcase(to_string(assignee_id)) == String.downcase(to_string(configured_assignee))
      end

    %{issue | assigned_to_worker: matches?}
  end

  defp normalize_assignee(nil), do: nil

  defp normalize_assignee(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_assignee(_), do: nil

  defp inspect_short(body) do
    body
    |> inspect(limit: 20, printable_limit: @max_error_body_log_bytes)
    |> truncate(@max_error_body_log_bytes)
  end

  defp truncate(s, n) when is_binary(s) and byte_size(s) > n,
    do: binary_part(s, 0, n) <> "...<truncated>"

  defp truncate(s, _), do: s
end
