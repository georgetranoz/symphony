defmodule SymphonyElixir.Control.TaskRun do
  @moduledoc """
  One execution attempt of a task. Tasks can have many runs (retries, fix
  passes, etc.). Each run captures timing, token usage, cost, and a pointer
  to its Codex session log.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Control.Task

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "task_runs" do
    belongs_to :task, Task

    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :exit_reason, :string
    field :tokens_in, :integer
    field :tokens_out, :integer
    field :cost_estimate_usd, :decimal
    field :codex_session_id, :string
    field :log_path, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :task_id,
      :started_at,
      :finished_at,
      :exit_reason,
      :tokens_in,
      :tokens_out,
      :cost_estimate_usd,
      :codex_session_id,
      :log_path
    ])
    |> validate_required([:task_id, :started_at])
  end
end
