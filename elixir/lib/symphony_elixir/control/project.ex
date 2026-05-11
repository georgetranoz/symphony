defmodule SymphonyElixir.Control.Project do
  @moduledoc """
  A project the orchestrator can dispatch tasks against. Carries the local
  git repo path, default branch, and LLM/coder defaults that newly created
  tasks pre-fill from.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Control.Provider

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @coder_kinds ~w(codex claude_code)
  @modes ~w(single two_phase)

  schema "projects" do
    field :name, :string
    field :repo_path, :string
    field :default_branch, :string, default: "main"
    field :verification_command, :string

    belongs_to :default_orchestrator_provider, Provider
    field :default_orchestrator_model, :string

    field :default_coder_kind, :string, default: "codex"
    belongs_to :default_coder_provider, Provider
    field :default_coder_model, :string

    field :default_mode, :string, default: "single"

    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :repo_path,
      :default_branch,
      :verification_command,
      :default_orchestrator_provider_id,
      :default_orchestrator_model,
      :default_coder_kind,
      :default_coder_provider_id,
      :default_coder_model,
      :default_mode,
      :archived_at
    ])
    |> validate_required([:name, :repo_path, :default_branch, :default_coder_kind, :default_mode])
    |> validate_inclusion(:default_coder_kind, @coder_kinds)
    |> validate_inclusion(:default_mode, @modes)
    |> unique_constraint(:name)
  end

  @doc "Supported coder kinds."
  @spec coder_kinds() :: [String.t()]
  def coder_kinds, do: @coder_kinds

  @doc "Supported execution modes."
  @spec modes() :: [String.t()]
  def modes, do: @modes
end
