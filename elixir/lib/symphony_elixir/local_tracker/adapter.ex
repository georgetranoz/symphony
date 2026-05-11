defmodule SymphonyElixir.LocalTracker.Adapter do
  @moduledoc """
  Tracker adapter that reads from and writes to the local control-plane
  SQLite database. Implements `SymphonyElixir.Tracker` so the orchestrator
  can dispatch tasks queued by the LiveView dashboard.

  ## State model

  Task lifecycle statuses live in `SymphonyElixir.Control.Task`. This adapter
  maps each status onto a "state" name (the same field Linear/GitHub use):

      Task.statuses() = [
        new       → not yet dispatchable (user is editing/triaging)
        queued    → ready to dispatch
        planning  → orchestrator pass running (two-phase mode)
        in_progress → coder pass running
        reviewing → orchestrator reviewing coder's output
        stopped   → manually stopped, agent should not be dispatched
        failed    → terminal: agent exited unsuccessfully
        done      → terminal: completed
      ]

  The `active_states` returned to Symphony are `queued/planning/in_progress/
  reviewing`; the `terminal_states` are `stopped/failed/done`. WORKFLOW.md
  doesn't need to declare these explicitly — defaults match exactly.

  Only root tasks (`parent_task_id IS NULL`) are dispatched. Sub-tasks are
  managed by an orchestrator pass and not surfaced to Symphony's top-level
  dispatch loop.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Control
  alias SymphonyElixir.Control.Task, as: ControlTask
  alias SymphonyElixir.Linear.Issue

  # ─── Tracker callbacks ────────────────────────────────────────────────

  @impl true
  def fetch_candidate_issues do
    actives = ControlTask.active_statuses()
    issues =
      Control.list_tasks_by_status(actives)
      |> Enum.filter(&is_nil(&1.parent_task_id))
      |> Enum.map(&to_issue/1)

    {:ok, issues}
  end

  @impl true
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized = state_names |> Enum.map(&to_string/1) |> Enum.uniq()

    if normalized == [] do
      {:ok, []}
    else
      issues =
        normalized
        |> Control.list_tasks_by_status()
        |> Enum.filter(&is_nil(&1.parent_task_id))
        |> Enum.map(&to_issue/1)

      {:ok, issues}
    end
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids) |> Enum.reject(&(&1 in [nil, ""]))

    issues =
      ids
      |> Control.get_tasks_by_ids()
      |> Enum.map(&to_issue/1)

    {:ok, issues}
  end

  @impl true
  def create_comment(task_id, body) when is_binary(task_id) and is_binary(body) do
    case Control.get_task(task_id) do
      nil ->
        {:error, :task_not_found}

      task ->
        run_attrs = %{
          task_id: task.id,
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now(),
          exit_reason: "comment",
          log_path: nil,
          codex_session_id: nil
        }

        # Comments from agents are persisted as task_run entries with the body
        # captured in exit_reason for now (richer modelling can come later).
        case Control.create_task_run(Map.put(run_attrs, :exit_reason, "comment: " <> truncate(body, 1000))) do
          {:ok, _run} -> :ok
          {:error, _changeset} -> {:error, :comment_persist_failed}
        end
    end
  end

  @impl true
  def update_issue_state(task_id, state_name)
      when is_binary(task_id) and is_binary(state_name) do
    statuses = ControlTask.statuses()

    cond do
      state_name not in statuses ->
        {:error, {:unknown_status, state_name}}

      true ->
        case Control.get_task(task_id) do
          nil ->
            {:error, :task_not_found}

          task ->
            case Control.transition_task(task, state_name) do
              {:ok, _task} -> :ok
              {:error, _changeset} -> {:error, :state_update_failed}
            end
        end
    end
  end

  # ─── private ──────────────────────────────────────────────────────────

  defp to_issue(%ControlTask{} = task) do
    %Issue{
      id: task.id,
      identifier: "T-" <> short_id(task.id),
      title: task.title,
      description: task.body,
      priority: task.priority,
      state: task.status,
      branch_name: build_branch_name(task),
      url: nil,
      assignee_id: nil,
      blocked_by: [],
      labels: [task.template],
      assigned_to_worker: true,
      created_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp build_branch_name(%ControlTask{branch_name: branch}) when is_binary(branch) and branch != "" do
    branch
  end

  defp build_branch_name(%ControlTask{title: title, id: id}) do
    slug =
      (title || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 40)

    short = short_id(id)
    if slug == "", do: "task-" <> short, else: "task-" <> short <> "-" <> slug
  end

  defp short_id(uuid) when is_binary(uuid) do
    uuid
    |> String.replace("-", "")
    |> binary_part(0, 8)
  end

  defp short_id(_), do: "00000000"

  defp truncate(s, n) when is_binary(s) and byte_size(s) > n, do: binary_part(s, 0, n) <> "..."
  defp truncate(s, _), do: s
end
