defmodule SymphonyElixir.Control do
  @moduledoc """
  Public API over the local control-plane database. Providers, projects,
  tasks, and task runs.

  This module is the single point of contact for both:

    * the LiveView dashboard (which renders projects/tasks and writes user
      edits), and
    * the local tracker adapter (which reads queued tasks and writes status
      transitions back as Symphony makes progress).

  Keep query and write logic here rather than scattering Ecto across the
  schemas or LiveView files.
  """

  import Ecto.Query, warn: false

  alias SymphonyElixir.Repo
  alias SymphonyElixir.Control.{Project, Provider, Task, TaskRun}

  # ─── providers ─────────────────────────────────────────────────────────

  @spec list_providers() :: [Provider.t()]
  def list_providers, do: Repo.all(from p in Provider, order_by: [asc: p.name])

  @spec get_provider(binary()) :: Provider.t() | nil
  def get_provider(id), do: Repo.get(Provider, id)

  @spec get_provider_by_name(String.t()) :: Provider.t() | nil
  def get_provider_by_name(name), do: Repo.get_by(Provider, name: name)

  @spec create_provider(map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def create_provider(attrs) do
    %Provider{} |> Provider.changeset(attrs) |> Repo.insert()
  end

  @spec update_provider(Provider.t(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def update_provider(%Provider{} = provider, attrs) do
    provider |> Provider.changeset(attrs) |> Repo.update()
  end

  @spec delete_provider(Provider.t()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def delete_provider(%Provider{} = provider), do: Repo.delete(provider)

  # ─── projects ──────────────────────────────────────────────────────────

  @spec list_projects(keyword()) :: [Project.t()]
  def list_projects(opts \\ []) do
    include_archived? = Keyword.get(opts, :include_archived, false)

    query = from p in Project, order_by: [asc: p.name]
    query = if include_archived?, do: query, else: from(p in query, where: is_nil(p.archived_at))
    Repo.all(query)
  end

  @spec get_project(binary()) :: Project.t() | nil
  def get_project(id), do: Repo.get(Project, id)

  @spec get_project_by_name(String.t()) :: Project.t() | nil
  def get_project_by_name(name), do: Repo.get_by(Project, name: name)

  @spec create_project(map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def create_project(attrs) do
    %Project{} |> Project.changeset(attrs) |> Repo.insert()
  end

  @spec update_project(Project.t(), map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def update_project(%Project{} = project, attrs) do
    project |> Project.changeset(attrs) |> Repo.update()
  end

  @spec archive_project(Project.t()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def archive_project(%Project{} = project) do
    update_project(project, %{archived_at: DateTime.utc_now()})
  end

  # ─── tasks ─────────────────────────────────────────────────────────────

  @spec list_tasks(binary() | nil) :: [Task.t()]
  def list_tasks(project_id \\ nil) do
    query =
      from t in Task,
        order_by: [asc: t.priority, asc: t.inserted_at]

    query = if project_id, do: from(t in query, where: t.project_id == ^project_id), else: query
    Repo.all(query)
  end

  @spec list_active_tasks() :: [Task.t()]
  def list_active_tasks do
    actives = Task.active_statuses()

    from(t in Task,
      where: t.status in ^actives and is_nil(t.parent_task_id),
      order_by: [asc: t.priority, asc: t.inserted_at]
    )
    |> Repo.all()
  end

  @spec list_tasks_by_status([String.t()]) :: [Task.t()]
  def list_tasks_by_status(statuses) when is_list(statuses) do
    from(t in Task,
      where: t.status in ^statuses,
      order_by: [asc: t.priority, asc: t.inserted_at]
    )
    |> Repo.all()
  end

  @spec get_task(binary()) :: Task.t() | nil
  def get_task(id), do: Repo.get(Task, id)

  @spec get_tasks_by_ids([binary()]) :: [Task.t()]
  def get_tasks_by_ids([]), do: []
  def get_tasks_by_ids(ids) when is_list(ids) do
    from(t in Task, where: t.id in ^ids) |> Repo.all()
  end

  @spec create_task(map()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    %Task{} |> Task.changeset(attrs) |> Repo.insert()
  end

  @spec update_task(Task.t(), map()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def update_task(%Task{} = task, attrs) do
    task |> Task.changeset(attrs) |> Repo.update()
  end

  @doc """
  Move a task to a new status. Convenience wrapper that also stamps
  `started_at` on transition into an active state and `finished_at` on
  transition into a terminal state.
  """
  @spec transition_task(Task.t(), String.t()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def transition_task(%Task{} = task, new_status) do
    now = DateTime.utc_now()

    base = %{status: new_status}

    base =
      cond do
        new_status in Task.active_statuses() and is_nil(task.started_at) ->
          Map.put(base, :started_at, now)

        new_status in Task.terminal_statuses() ->
          Map.put(base, :finished_at, now)

        true ->
          base
      end

    update_task(task, base)
  end

  # ─── task runs ─────────────────────────────────────────────────────────

  @spec list_task_runs(binary()) :: [TaskRun.t()]
  def list_task_runs(task_id) do
    from(r in TaskRun, where: r.task_id == ^task_id, order_by: [desc: r.started_at])
    |> Repo.all()
  end

  @spec create_task_run(map()) :: {:ok, TaskRun.t()} | {:error, Ecto.Changeset.t()}
  def create_task_run(attrs) do
    %TaskRun{} |> TaskRun.changeset(attrs) |> Repo.insert()
  end

  @spec update_task_run(TaskRun.t(), map()) :: {:ok, TaskRun.t()} | {:error, Ecto.Changeset.t()}
  def update_task_run(%TaskRun{} = run, attrs) do
    run |> TaskRun.changeset(attrs) |> Repo.update()
  end
end
