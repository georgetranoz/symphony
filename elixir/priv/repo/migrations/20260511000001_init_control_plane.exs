defmodule SymphonyElixir.Repo.Migrations.InitControlPlane do
  use Ecto.Migration

  def change do
    # --- providers --------------------------------------------------------
    # An LLM credential record. The api_key field stores a Keychain reference
    # (e.g. "keychain:Symphony/anthropic-georgetranoz") rather than the raw
    # secret. Resolution happens at call time via SymphonyElixir.Keychain.
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false
      add :base_url, :string, null: false
      add :api_key_ref, :string, null: false
      add :models, :map, default: %{}
      add :models_refreshed_at, :utc_datetime_usec
      add :last_error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:providers, [:name])

    # --- projects ---------------------------------------------------------
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :repo_path, :string, null: false
      add :default_branch, :string, default: "main", null: false
      add :verification_command, :string

      # Default LLM choices when a task doesn't override.
      add :default_orchestrator_provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
      add :default_orchestrator_model, :string
      add :default_coder_kind, :string, default: "codex", null: false
      add :default_coder_provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
      add :default_coder_model, :string
      add :default_mode, :string, default: "single", null: false

      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:name])

    # --- tasks ------------------------------------------------------------
    # Recursive: a sub-task carries parent_task_id. Roots have nil parent.
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)

      add :title, :string, null: false
      add :body, :text
      add :template, :string, default: "feature", null: false

      # 1 = highest, 4 = lowest. Mirrors Linear's priority spectrum.
      add :priority, :integer, default: 2, null: false

      add :status, :string, default: "new", null: false
      add :mode, :string, default: "single", null: false

      # Per-task LLM overrides (null = use project default).
      add :orchestrator_provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
      add :orchestrator_model, :string
      add :coder_kind, :string
      add :coder_provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
      add :coder_model, :string

      # Sub-task fan-out fields. Unused for single-mode roots.
      add :files_owned, {:array, :string}, default: []
      add :depends_on_task_ids, {:array, :binary_id}, default: []

      add :workspace_path, :string
      add :branch_name, :string
      add :verification_command, :string

      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:project_id, :status])
    create index(:tasks, [:parent_task_id])
    create index(:tasks, [:status, :priority, :inserted_at])

    # --- task_runs --------------------------------------------------------
    create table(:task_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :exit_reason, :string
      add :tokens_in, :integer
      add :tokens_out, :integer
      add :cost_estimate_usd, :decimal
      add :codex_session_id, :string
      add :log_path, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:task_runs, [:task_id, :started_at])
  end
end
