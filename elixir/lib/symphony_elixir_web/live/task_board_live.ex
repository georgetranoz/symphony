defmodule SymphonyElixirWeb.TaskBoardLive do
  @moduledoc """
  Kanban board for tasks under a single project. Six columns covering the
  lifecycle (New, Queued, In progress, Stopped, Failed, Done). Clicking a
  card opens a modal-style panel where the full task spec can be edited.

  Routes:
    /projects/:id/board                – board view (live_action: :index)
    /projects/:id/tasks/new            – new-task panel  (:new_task)
    /projects/:id/tasks/:task_id       – existing-task panel (:show_task)
  """

  use Phoenix.LiveView

  alias SymphonyElixir.Control
  alias SymphonyElixir.Control.Task

  @columns [
    {"new", "New"},
    {"queued", "Queued"},
    {"in_progress", "In progress"},
    {"stopped", "Stopped"},
    {"failed", "Failed"},
    {"done", "Done"}
  ]

  @templates_with_seeds [
    {"feature", "Feature",
     "## What\n\n<describe the user-visible behaviour>\n\n## Why\n\n<short motivation>\n\n## Acceptance\n\n- [ ] <criterion 1>"},
    {"bug", "Bug",
     "## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n\n## Suspected root cause\n"},
    {"refactor", "Refactor",
     "## What needs restructuring\n\n## Why now\n\n## Non-goals\n\n- Behaviour must remain identical.\n"},
    {"chore", "Chore", "## Task\n\n<small mechanical change>\n"},
    {"spike", "Spike",
     "## Question\n\n## Time-box\n\n<e.g. 2 hours>\n\n## Deliverable\n\nA written conclusion in the body of this task.\n"}
  ]

  @impl true
  def mount(%{"id" => project_id} = _params, _session, socket) do
    case Control.get_project(project_id) do
      nil ->
        {:ok, socket |> redirect(to: "/projects")}

      project ->
        if connected?(socket), do: :timer.send_interval(3_000, self(), :refresh)

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(:providers, Control.list_providers())
         |> assign(:tasks, Control.list_tasks(project.id))
         |> assign(:columns, @columns)
         |> assign(:template_seeds, @templates_with_seeds)
         |> assign(:flash_message, nil)
         |> assign(:flash_kind, :info)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:active_task, nil) |> assign(:form, nil)
  end

  defp apply_action(socket, :new_task, _params) do
    project = socket.assigns.project

    seed = %Task{
      project_id: project.id,
      template: "feature",
      priority: 2,
      status: "new",
      mode: project.default_mode || "single",
      coder_kind: project.default_coder_kind,
      coder_provider_id: project.default_coder_provider_id,
      coder_model: project.default_coder_model,
      orchestrator_provider_id: project.default_orchestrator_provider_id,
      orchestrator_model: project.default_orchestrator_model,
      verification_command: project.verification_command
    }

    socket |> assign(:active_task, seed) |> assign(:form, task_to_form(seed))
  end

  defp apply_action(socket, :show_task, %{"task_id" => task_id}) do
    case Control.get_task(task_id) do
      nil -> socket |> redirect(to: "/projects/#{socket.assigns.project.id}/board")
      task -> socket |> assign(:active_task, task) |> assign(:form, task_to_form(task))
    end
  end

  # ─── events ───────────────────────────────────────────────────────────

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :tasks, Control.list_tasks(socket.assigns.project.id))}
  end

  @impl true
  def handle_event("template_picked", %{"task" => %{"template" => template}}, socket) do
    seed_body = Enum.find_value(@templates_with_seeds, fn {t, _label, seed} -> t == template && seed end)
    form = socket.assigns.form |> Map.put("template", template) |> Map.put("body", seed_body || socket.assigns.form["body"])
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_task", %{"task" => attrs}, socket) do
    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put("project_id", socket.assigns.project.id)
      |> Map.put_new("status", "new")

    result =
      case socket.assigns.active_task do
        %Task{id: nil} -> Control.create_task(attrs)
        existing -> Control.update_task(existing, attrs)
      end

    case result do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:tasks, Control.list_tasks(socket.assigns.project.id))
         |> push_patch(to: "/projects/#{socket.assigns.project.id}/board")
         |> flash(:info, "Saved.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, flash(socket, :error, "Save failed: #{format_errors(cs)}.")}
    end
  end

  def handle_event("transition", %{"id" => id, "status" => status}, socket) do
    case Control.get_task(id) do
      nil ->
        {:noreply, flash(socket, :error, "Task not found.")}

      task ->
        case Control.transition_task(task, status) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:tasks, Control.list_tasks(socket.assigns.project.id))
             |> flash(:info, "Moved \"#{task.title}\" → #{status}.")}

          {:error, _} ->
            {:noreply, flash(socket, :error, "Transition failed.")}
        end
    end
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, push_patch(socket, to: "/projects/#{socket.assigns.project.id}/board")}
  end

  # ─── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1400px; margin: 24px auto; font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2937;">
      <header style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <div>
          <nav style="display: flex; gap: 12px; font-size: 13px; color: #6b7280; margin-bottom: 6px;">
            <.link navigate="/projects" style="color: #2563eb; text-decoration: none;">Projects</.link>
            <span>›</span>
            <span>{@project.name}</span>
          </nav>
          <h1 style="font-size: 24px; margin: 0;">{@project.name}</h1>
        </div>
        <div style="display: flex; gap: 12px;">
          <.link patch={"/projects/#{@project.id}/tasks/new"}
            style="padding: 8px 14px; background: #2563eb; color: white; border-radius: 6px; text-decoration: none; font-weight: 600;">
            + New task
          </.link>
          <.link navigate={"/projects/#{@project.id}/edit"}
            style="padding: 8px 14px; background: #f3f4f6; color: #1f2937; border-radius: 6px; text-decoration: none;">
            Edit project
          </.link>
        </div>
      </header>

      <%= if @flash_message do %>
        <div style={"padding: 10px 14px; border-radius: 8px; margin-bottom: 16px; background: #{flash_bg(@flash_kind)}; color: #{flash_fg(@flash_kind)};"}>
          {@flash_message}
        </div>
      <% end %>

      <div style="display: grid; grid-template-columns: repeat(6, minmax(180px, 1fr)); gap: 12px; align-items: start;">
        <%= for {status, label} <- @columns do %>
          <div style="background: #f3f4f6; border-radius: 10px; padding: 10px; min-height: 320px;">
            <h2 style="font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; color: #4b5563; margin: 4px 6px 10px; display: flex; align-items: center; justify-content: space-between;">
              <span>{label}</span>
              <span style="font-weight: 400; color: #9ca3af;">{column_count(@tasks, status)}</span>
            </h2>
            <div style="display: grid; gap: 8px;">
              <%= for task <- column_tasks(@tasks, status) do %>
                <.link patch={"/projects/#{@project.id}/tasks/#{task.id}"}
                  style="display: block; background: white; border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px 12px; text-decoration: none; color: inherit; box-shadow: 0 1px 1px rgba(0,0,0,0.03);">
                  <div style="display: flex; justify-content: space-between; gap: 6px; align-items: baseline;">
                    <strong style="font-size: 13px; line-height: 1.3;">{task.title}</strong>
                    <span style={"font-size: 10px; padding: 1px 5px; border-radius: 3px; #{template_badge_style(task.template)}"}>{task.template}</span>
                  </div>
                  <div style="font-size: 11px; color: #6b7280; margin-top: 4px;">
                    P{task.priority} · {task.mode}{coder_summary(task)}
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @active_task do %>
        <.task_panel project={@project} task={@active_task} form={@form} providers={@providers}
          template_seeds={@template_seeds} columns={@columns} />
      <% end %>
    </div>
    """
  end

  # ─── inline components ────────────────────────────────────────────────

  attr :project, :map, required: true
  attr :task, :map, required: true
  attr :form, :map, required: true
  attr :providers, :list, required: true
  attr :template_seeds, :list, required: true
  attr :columns, :list, required: true

  defp task_panel(assigns) do
    ~H"""
    <div phx-window-keydown="close_panel" phx-key="escape"
      style="position: fixed; inset: 0; background: rgba(15, 23, 42, 0.45); display: flex; align-items: flex-start; justify-content: center; padding: 32px 16px; z-index: 100;">
      <div style="background: white; border-radius: 12px; max-width: 720px; width: 100%; max-height: calc(100vh - 64px); overflow: auto; box-shadow: 0 20px 50px rgba(0,0,0,0.2);">
        <header style="display: flex; justify-content: space-between; align-items: center; padding: 16px 20px; border-bottom: 1px solid #e5e7eb;">
          <h2 style="margin: 0; font-size: 18px;">
            <%= if @task.id, do: "Edit task", else: "New task" %>
          </h2>
          <button phx-click="close_panel"
            style="background: transparent; border: 0; color: #6b7280; font-size: 20px; cursor: pointer;">×</button>
        </header>

        <form phx-submit="save_task" phx-change="template_picked" style="padding: 20px; display: grid; gap: 14px;">
          <input type="hidden" name="task[id]" value={@task.id} />

          <label style="display: flex; flex-direction: column; gap: 4px;">
            <span style="font-size: 12px; color: #6b7280;">Title</span>
            <input type="text" name="task[title]" value={@form["title"]}
              style="padding: 9px 11px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 15px;" />
          </label>

          <div style="display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 10px;">
            <label style="display: flex; flex-direction: column; gap: 4px;">
              <span style="font-size: 12px; color: #6b7280;">Template</span>
              <select name="task[template]" style="padding: 7px 9px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;">
                <%= for {val, label, _seed} <- @template_seeds do %>
                  <option value={val} selected={val == @form["template"]}>{label}</option>
                <% end %>
              </select>
            </label>

            <label style="display: flex; flex-direction: column; gap: 4px;">
              <span style="font-size: 12px; color: #6b7280;">Priority</span>
              <select name="task[priority]" style="padding: 7px 9px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;">
                <%= for p <- 1..4 do %>
                  <option value={p} selected={to_string(p) == to_string(@form["priority"])}>P{p}</option>
                <% end %>
              </select>
            </label>

            <label style="display: flex; flex-direction: column; gap: 4px;">
              <span style="font-size: 12px; color: #6b7280;">Status</span>
              <select name="task[status]" style="padding: 7px 9px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;">
                <%= for {val, label} <- @columns do %>
                  <option value={val} selected={val == @form["status"]}>{label}</option>
                <% end %>
              </select>
            </label>

            <label style="display: flex; flex-direction: column; gap: 4px;">
              <span style="font-size: 12px; color: #6b7280;">Mode</span>
              <select name="task[mode]" style="padding: 7px 9px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px;">
                <option value="single" selected={@form["mode"] == "single"}>Single coder</option>
                <option value="two_phase" selected={@form["mode"] == "two_phase"}>Two-phase</option>
              </select>
            </label>
          </div>

          <label style="display: flex; flex-direction: column; gap: 4px;">
            <span style="font-size: 12px; color: #6b7280;">Spec / body</span>
            <textarea name="task[body]" rows="10"
              style="padding: 10px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 13px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.5; resize: vertical;">{@form["body"]}</textarea>
          </label>

          <details style="background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;">
            <summary style="padding: 10px 14px; cursor: pointer; font-size: 13px; color: #4b5563; font-weight: 600;">LLM overrides (leave blank to use project defaults)</summary>
            <div style="padding: 0 14px 14px; display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Orchestrator provider</span>
                <select name="task[orchestrator_provider_id]" style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px;">
                  <option value=""></option>
                  <%= for prov <- @providers do %>
                    <option value={prov.id} selected={to_string(prov.id) == to_string(@form["orchestrator_provider_id"])}>{prov.name}</option>
                  <% end %>
                </select>
              </label>
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Orchestrator model</span>
                <input type="text" name="task[orchestrator_model]" value={@form["orchestrator_model"]}
                  style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px;" />
              </label>
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Coder kind</span>
                <select name="task[coder_kind]" style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px;">
                  <option value=""></option>
                  <option value="codex" selected={@form["coder_kind"] == "codex"}>Codex CLI</option>
                  <option value="claude_code" selected={@form["coder_kind"] == "claude_code"}>Claude Code</option>
                </select>
              </label>
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Coder provider</span>
                <select name="task[coder_provider_id]" style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px;">
                  <option value=""></option>
                  <%= for prov <- @providers do %>
                    <option value={prov.id} selected={to_string(prov.id) == to_string(@form["coder_provider_id"])}>{prov.name}</option>
                  <% end %>
                </select>
              </label>
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Coder model</span>
                <input type="text" name="task[coder_model]" value={@form["coder_model"]}
                  style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px;" />
              </label>
              <label style="display: flex; flex-direction: column; gap: 4px;">
                <span style="font-size: 11px; color: #6b7280;">Verification command</span>
                <input type="text" name="task[verification_command]" value={@form["verification_command"]}
                  placeholder="defaults to project's" style="padding: 6px 8px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 12px; font-family: monospace;" />
              </label>
            </div>
          </details>

          <div style="display: flex; gap: 10px; margin-top: 4px;">
            <button type="submit" style="padding: 9px 16px; background: #2563eb; color: white; border: 0; border-radius: 6px; font-weight: 600; cursor: pointer;">
              Save task
            </button>
            <button type="button" phx-click="close_panel"
              style="padding: 9px 16px; background: white; color: #4b5563; border: 1px solid #d1d5db; border-radius: 6px; cursor: pointer;">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  defp column_tasks(tasks, status) do
    tasks
    |> Enum.filter(&(&1.status == status and is_nil(&1.parent_task_id)))
    |> Enum.sort_by(&{&1.priority, &1.inserted_at})
  end

  defp column_count(tasks, status), do: tasks |> column_tasks(status) |> length()

  defp template_badge_style("bug"), do: "background: #fef2f2; color: #b91c1c;"
  defp template_badge_style("feature"), do: "background: #eef2ff; color: #4338ca;"
  defp template_badge_style("refactor"), do: "background: #f0fdf4; color: #15803d;"
  defp template_badge_style("chore"), do: "background: #f3f4f6; color: #4b5563;"
  defp template_badge_style("spike"), do: "background: #fffbeb; color: #92400e;"
  defp template_badge_style(_), do: "background: #f3f4f6; color: #4b5563;"

  defp coder_summary(%Task{coder_kind: nil}), do: ""
  defp coder_summary(%Task{coder_kind: kind, coder_model: nil}), do: " · " <> kind
  defp coder_summary(%Task{coder_kind: kind, coder_model: model}), do: " · " <> kind <> "/" <> model

  defp task_to_form(%Task{} = t) do
    %{
      "id" => t.id || "",
      "title" => t.title || "",
      "body" => t.body || "",
      "template" => t.template || "feature",
      "priority" => t.priority || 2,
      "status" => t.status || "new",
      "mode" => t.mode || "single",
      "orchestrator_provider_id" => t.orchestrator_provider_id || "",
      "orchestrator_model" => t.orchestrator_model || "",
      "coder_kind" => t.coder_kind || "",
      "coder_provider_id" => t.coder_provider_id || "",
      "coder_model" => t.coder_model || "",
      "verification_command" => t.verification_command || ""
    }
  end

  defp normalize_attrs(attrs) do
    attrs
    |> Map.delete("id")
    |> Enum.map(fn
      {k, ""} -> {k, nil}
      pair -> pair
    end)
    |> Map.new()
  end

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
