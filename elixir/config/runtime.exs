import Config

# Resolve the SQLite database path at boot. Honours SYMPHONY_DB_PATH if set,
# else falls back to ~/.symphony/db.sqlite. The directory is created at app
# start before the Repo is supervised.
config :symphony_elixir, SymphonyElixir.Repo,
  database: SymphonyElixir.Repo.default_database_path()
