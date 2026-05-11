defmodule SymphonyElixirWeb.ProjectsLive do
  @moduledoc """
  LiveView for managing projects. Index lists active and archived projects.
  New/edit shares a form that lets the user pick defaults from the configured
  providers (M3).
  """

  use Phoenix.LiveView

  alias SymphonyElixir.Control
  alias SymphonyElixir.Control.{Project, Provider}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:providers, Control.list_providers())
     |> assign(:projects, Control.list_projects(include_archived: true))
     |> assign(:flash_message, nil)
     |> assign(:flash_kind, :info)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:project, nil) |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:project, %Project{})
    |> assign(:form, project_to_form(%Project{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Control.get_project(id) do
      nil -> socket |> redirect(to: "/projects")
      project -> socket |> assign(:project, project) |> assign(:form, project_to_form(project))
    end
  end

  # ─── events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("save", %{"project" => attrs}, socket) do
    attrs = normalize_attrs(attrs)

    result =
      case socket.assigns.project do
        %Project{id: nil} -> Control.create_project(attrs)
        existing -> Control.update_project(existing, attrs)
      end

    case result do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(:projects, Control.list_projects(include_archived: true))
         |> flash(:info, "Saved.")
         |> push_navigate(to: "/projects")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, flash(socket, :error, "Save failed: #{format_errors(cs)}.")}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    case Control.get_project(id) do
      nil ->
        {:noreply, flash(socket, :error, "Project not found.")}

      project ->
        {:ok, _} = Control.archive_project(project)

        {:noreply,
         socket
         |> assign(:projects, Control.list_projects(include_archived: true))
         |> flash(:info, "Archived \"#{project.name}\".")}
    end
  end

  # ─── render ───────────────────────────────────────────────────────────

  @impl true
  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <div style="max-width: 800px; margin: 24px auto; font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2937;">
      <header style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px;">
        <h1 style="font-size: 24px; margin: 0;">
          <%= if @project.id, do: "Edit project", else: "New project" %>
        </h1>
        <.link navigate="/projects" style="color: #2563eb; text-decoration: none;">← Back</.link>
      </header>

      <%= if @flash_message do %>
        <div style={"padding: 12px 16px; border-radius: 8px; margin-bottom: 16px; background: #{flash_bg(@flash_kind)}; color: #{flash_fg(@flash_kind)};"}>
          {@flash_message}
        </div>
      <% end %>

      <form phx-submit="save" style="display: grid; gap: 16px;">
        <.text_field label="Project name" name="project[name]" value={@form["name"]} placeholder="e.g. inkfortress-webapp" />
        <.text_field label="Repository path" name="project[repo_path]" value={@form["repo_path"]} placeholder="/Volumes/Morgana/Dev/Ink Fortress/WebApp" />
        <.text_field label="Default branch" name="project[default_branch]" value={@form["default_branch"]} />
        <.text_field label="Verification command (optional)" name="project[verification_command]" value={@form["verification_command"]} placeholder="e.g. npm test --silent" />

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; background: #f9fafb; padding: 16px; border-radius: 8px; border: 1px solid #e5e7eb;">
          <h3 style="grid-column: 1 / span 2; margin: 0 0 4px; font-size: 14px; color: #4b5563;">Default orchestrator LLM (optional)</h3>
          <.select_field label="Provider" name="project[default_orchestrator_provider_id]" value={@form["default_orchestrator_provider_id"]}
            options={provider_options(@providers)} />
          <.text_field label="Model" name="project[default_orchestrator_model]" value={@form["default_orchestrator_model"]} placeholder="claude-opus-4-5" />
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; background: #f9fafb; padding: 16px; border-radius: 8px; border: 1px solid #e5e7eb;">
          <h3 style="grid-column: 1 / span 2; margin: 0 0 4px; font-size: 14px; color: #4b5563;">Default coder</h3>
          <.select_field label="Coder kind" name="project[default_coder_kind]" value={@form["default_coder_kind"]}
            options={[{"Codex CLI", "codex"}, {"Claude Code", "claude_code"}]} />
          <.select_field label="Default mode" name="project[default_mode]" value={@form["default_mode"]}
            options={[{"Single coder", "single"}, {"Two-phase (orchestrator → fan-out)", "two_phase"}]} />
          <.select_field label="Provider" name="project[default_coder_provider_id]" value={@form["default_coder_provider_id"]}
            options={provider_options(@providers)} />
          <.text_field label="Model" name="project[default_coder_model]" value={@form["default_coder_model"]} placeholder="deepseek-v4-pro" />
        </div>

        <div style="display: flex; gap: 12px; margin-top: 8px;">
          <button type="submit" style="padding: 9px 16px; background: #2563eb; color: white; border: 0; border-radius: 6px; font-weight: 600; cursor: pointer;">
            Save project
          </button>
          <.link navigate="/projects" style="padding: 9px 16px; color: #4b5563; text-decoration: none; border: 1px solid #d1d5db; border-radius: 6px;">
            Cancel
          </.link>
        </div>
      </form>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="max-width: 980px; margin: 24px auto; font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2937;">
      <header style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px;">
        <h1 style="font-size: 28px; margin: 0;">Projects</h1>
        <nav style="display: flex; gap: 16px;">
          <.link navigate="/" style="color: #2563eb; text-decoration: none;">Dashboard</.link>
          <.link navigate="/projects" style="color: #1f2937; font-weight: 600;">Projects</.link>
          <.link navigate="/providers" style="color: #2563eb; text-decoration: none;">Providers</.link>
        </nav>
      </header>

      <%= if @flash_message do %>
        <div style={"padding: 12px 16px; border-radius: 8px; margin-bottom: 16px; background: #{flash_bg(@flash_kind)}; color: #{flash_fg(@flash_kind)};"}>
          {@flash_message}
        </div>
      <% end %>

      <div style="margin-bottom: 16px;">
        <.link navigate="/projects/new" style="padding: 8px 14px; background: #2563eb; color: white; border-radius: 6px; text-decoration: none; font-weight: 600;">
          New project
        </.link>
      </div>

      <%= if @projects == [] do %>
        <p style="color: #9ca3af;">No projects yet.</p>
      <% else %>
        <ul style="list-style: none; padding: 0; margin: 0; display: grid; gap: 12px;">
          <%= for p <- @projects do %>
            <li style={"display: grid; grid-template-columns: 1fr auto; gap: 4px 16px; padding: 14px 18px; border: 1px solid #e5e7eb; border-radius: 10px; background: #{if p.archived_at, do: "#f9fafb", else: "#ffffff"};"}>
              <div style="display: flex; gap: 8px; align-items: baseline;">
                <strong style="font-size: 16px;">{p.name}</strong>
                <%= if p.archived_at do %>
                  <span style="font-size: 11px; padding: 2px 6px; background: #f3f4f6; color: #6b7280; border-radius: 4px;">archived</span>
                <% end %>
              </div>
              <div style="display: flex; gap: 8px;">
                <.link navigate={"/projects/#{p.id}/board"} style="padding: 4px 10px; background: #eff6ff; color: #1d4ed8; border-radius: 4px; text-decoration: none; font-size: 12px;">Board</.link>
                <.link navigate={"/projects/#{p.id}/edit"} style="padding: 4px 10px; background: #f3f4f6; color: #1f2937; border-radius: 4px; text-decoration: none; font-size: 12px;">Edit</.link>
                <%= unless p.archived_at do %>
                  <button phx-click="archive" phx-value-id={p.id} data-confirm={"Archive \"#{p.name}\"?"}
                    style="padding: 4px 10px; background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; border-radius: 4px; font-size: 12px; cursor: pointer;">
                    Archive
                  </button>
                <% end %>
              </div>
              <div style="grid-column: 1 / span 2; font-family: monospace; font-size: 12px; color: #6b7280;">
                {p.repo_path} · branch {p.default_branch}
              </div>
              <div style="grid-column: 1 / span 2; font-size: 12px; color: #4b5563;">
                Coder: {p.default_coder_kind}{coder_model_note(p)} · Mode: {p.default_mode}
              </div>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  # ─── inline components ────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""

  defp text_field(assigns) do
    ~H"""
    <label style="display: flex; flex-direction: column; gap: 4px;">
      <span style="font-size: 12px; color: #6b7280;">{@label}</span>
      <input type="text" name={@name} value={@value} placeholder={@placeholder}
        style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px;" />
    </label>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true

  defp select_field(assigns) do
    ~H"""
    <label style="display: flex; flex-direction: column; gap: 4px;">
      <span style="font-size: 12px; color: #6b7280;">{@label}</span>
      <select name={@name} style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px;">
        <option value=""></option>
        <%= for {label, val} <- @options do %>
          <option value={val} selected={to_string(val) == to_string(@value)}>{label}</option>
        <% end %>
      </select>
    </label>
    """
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  defp provider_options(providers) do
    Enum.map(providers, fn %Provider{id: id, name: name} -> {name, id} end)
  end

  defp project_to_form(%Project{} = p) do
    %{
      "name" => p.name || "",
      "repo_path" => p.repo_path || "",
      "default_branch" => p.default_branch || "main",
      "verification_command" => p.verification_command || "",
      "default_orchestrator_provider_id" => p.default_orchestrator_provider_id || "",
      "default_orchestrator_model" => p.default_orchestrator_model || "",
      "default_coder_kind" => p.default_coder_kind || "codex",
      "default_coder_provider_id" => p.default_coder_provider_id || "",
      "default_coder_model" => p.default_coder_model || "",
      "default_mode" => p.default_mode || "single"
    }
  end

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.map(fn
      {k, ""} -> {k, nil}
      pair -> pair
    end)
    |> Map.new()
  end

  defp coder_model_note(%Project{default_coder_model: m}) when is_binary(m) and m != "",
    do: " (" <> m <> ")"

  defp coder_model_note(_), do: ""

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end) |> Enum.join(", ")
  end

  defp flash(socket, kind, msg) do
    socket |> assign(:flash_kind, kind) |> assign(:flash_message, msg)
  end

  defp flash_bg(:info), do: "#ecfdf5"
  defp flash_bg(:error), do: "#fef2f2"
  defp flash_bg(_), do: "#eff6ff"
  defp flash_fg(:info), do: "#065f46"
  defp flash_fg(:error), do: "#991b1b"
  defp flash_fg(_), do: "#1e3a8a"
end
