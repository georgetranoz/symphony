import Config

config :phoenix, :json_library, Jason

# Ecto / SQLite repo for the local control plane.
# The actual database path is resolved at boot from SYMPHONY_DB_PATH or
# `~/.symphony/db.sqlite` (see SymphonyElixir.Repo.database_path/0).
config :symphony_elixir,
  ecto_repos: [SymphonyElixir.Repo]

config :symphony_elixir, SymphonyElixir.Repo,
  journal_mode: :wal,
  pool_size: 5,
  show_sensitive_data_on_connection_error: false

config :symphony_elixir, SymphonyElixirWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SymphonyElixirWeb.ErrorHTML, json: SymphonyElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SymphonyElixir.PubSub,
  live_view: [signing_salt: "symphony-live-view"],
  secret_key_base: String.duplicate("s", 64),
  check_origin: false,
  server: false
