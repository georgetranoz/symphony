defmodule SymphonyElixir.Control.Provider do
  @moduledoc """
  An LLM credential record. The actual API key never lives in this row —
  `api_key_ref` is a Keychain lookup string resolved by
  `SymphonyElixir.Keychain.fetch/1` at call time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(anthropic openai deepseek google openrouter custom)

  schema "providers" do
    field :name, :string
    field :kind, :string
    field :base_url, :string
    field :api_key_ref, :string
    field :models, :map, default: %{}
    field :models_refreshed_at, :utc_datetime_usec
    field :last_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :name,
      :kind,
      :base_url,
      :api_key_ref,
      :models,
      :models_refreshed_at,
      :last_error
    ])
    |> validate_required([:name, :kind, :base_url, :api_key_ref])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:name)
  end

  @doc "List of supported provider kinds."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds
end
