defmodule SymphonyElixir.Control.Task do
  @moduledoc """
  A unit of work the orchestrator dispatches. Self-referential: sub-tasks
  created by an orchestrator pass live in the same table with `parent_task_id`
  set to their root.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Control.{Project, Provider}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @templates ~w(bug feature refactor chore spike)
  @statuses ~w(new queued planning in_progress reviewing stopped failed done)
  @modes ~w(single two_phase)
  @coder_kinds ~w(codex claude_code)
  @priorities 1..4

  schema "tasks" do
    belongs_to :project, Project
    belongs_to :parent_task, __MODULE__, foreign_key: :parent_task_id

    field :title, :string
    field :body, :string

    field :template, :string, default: "feature"
    field :priority, :integer, default: 2
    field :status, :string, default: "new"
    field :mode, :string, default: "single"

    belongs_to :orchestrator_provider, Provider
    field :orchestrator_model, :string
    field :coder_kind, :string
    belongs_to :coder_provider, Provider
    field :coder_model, :string

    field :files_owned, {:array, :string}, default: []
    field :depends_on_task_ids, {:array, :binary_id}, default: []

    field :workspace_path, :string
    field :branch_name, :string
    field :verification_command, :string

    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    has_many :sub_tasks, __MODULE__, foreign_key: :parent_task_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :project_id,
      :parent_task_id,
      :title,
      :body,
      :template,
      :priority,
      :status,
      :mode,
      :orchestrator_provider_id,
      :orchestrator_model,
      :coder_kind,
      :coder_provider_id,
      :coder_model,
      :files_owned,
      :depends_on_task_ids,
      :workspace_path,
      :branch_name,
      :verification_command,
      :started_at,
      :finished_at
    ])
    |> validate_required([:project_id, :title, :template, :priority, :status, :mode])
    |> validate_inclusion(:template, @templates)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:priority, Enum.to_list(@priorities))
    |> validate_change(:coder_kind, fn :coder_kind, value ->
      cond do
        is_nil(value) -> []
        value in @coder_kinds -> []
        true -> [coder_kind: "must be one of #{Enum.join(@coder_kinds, ", ")} (or null)"]
      end
    end)
  end

  @doc "Allowed task templates (Bug, Feature, Refactor, Chore, Spike)."
  @spec templates() :: [String.t()]
  def templates, do: @templates

  @doc "Lifecycle statuses a task can be in."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Statuses that the orchestrator should consider for dispatch."
  @spec active_statuses() :: [String.t()]
  def active_statuses, do: ~w(queued planning in_progress reviewing)

  @doc "Statuses that signal the orchestrator should stop tracking the task."
  @spec terminal_statuses() :: [String.t()]
  def terminal_statuses, do: ~w(stopped failed done)
end
