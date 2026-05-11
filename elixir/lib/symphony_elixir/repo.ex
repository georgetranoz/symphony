defmodule SymphonyElixir.Repo do
  @moduledoc """
  Ecto repo backing the local control-plane database (projects, tasks, providers).

  The database file lives at `~/.symphony/db.sqlite` by default and is created
  automatically at boot. The directory is created if missing.
  """

  use Ecto.Repo,
    otp_app: :symphony_elixir,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  Resolve the on-disk path the repo should use. Honoured by config/runtime
  helpers below and exposed for tooling (migrations, tests).
  """
  @spec database_path() :: String.t()
  def database_path do
    case Application.get_env(:symphony_elixir, __MODULE__, [])[:database] do
      nil -> default_database_path()
      "" -> default_database_path()
      path when is_binary(path) -> path
    end
  end

  @doc false
  def default_database_path do
    case System.get_env("SYMPHONY_DB_PATH") do
      nil -> Path.join([System.user_home!(), ".symphony", "db.sqlite"])
      "" -> Path.join([System.user_home!(), ".symphony", "db.sqlite"])
      path -> path
    end
  end

  @doc """
  Ensure the parent directory of the database file exists. Safe to call
  repeatedly; idempotent. Returns the resolved path.
  """
  @spec ensure_database_dir!() :: String.t()
  def ensure_database_dir! do
    path = database_path()
    path |> Path.dirname() |> File.mkdir_p!()
    path
  end
end
