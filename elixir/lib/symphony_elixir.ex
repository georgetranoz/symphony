defmodule SymphonyElixir do
  @moduledoc """
  Entry point for the Symphony orchestrator.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    SymphonyElixir.Orchestrator.start_link(opts)
  end
end

defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = SymphonyElixir.LogFile.configure()
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    SymphonyElixir.Repo.ensure_database_dir!()
    set_repo_database_path!()
    migrate_repo!()

    children = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
      SymphonyElixir.Repo,
      SymphonyElixir.WorkflowStore,
      SymphonyElixir.Orchestrator,
      SymphonyElixir.HttpServer,
      SymphonyElixir.StatusDashboard
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: SymphonyElixir.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    SymphonyElixir.StatusDashboard.render_offline_status()
    :ok
  end

  # Inject the resolved DB path into application env so the supervised Repo
  # picks it up. `runtime.exs` may not be evaluated for escripts, so we set
  # it here unconditionally — safe to call repeatedly.
  defp set_repo_database_path! do
    existing = Application.get_env(:symphony_elixir, SymphonyElixir.Repo, [])
    path = SymphonyElixir.Repo.database_path()
    Application.put_env(:symphony_elixir, SymphonyElixir.Repo, Keyword.put(existing, :database, path))
    :ok
  end

  # Run any pending Ecto migrations BEFORE the supervision tree starts, so
  # the Orchestrator's init can query the DB. Uses Ecto.Migrator.with_repo/2
  # which spins the Repo up just long enough to migrate, then stops it. The
  # supervised Repo will then restart cleanly as a tree child.
  defp migrate_repo! do
    migrations_path = Application.app_dir(:symphony_elixir, "priv/repo/migrations")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(SymphonyElixir.Repo, fn repo ->
        Ecto.Migrator.run(repo, migrations_path, :up, all: true)
      end)

    :ok
  end
end
