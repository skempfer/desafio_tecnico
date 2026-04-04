import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

config :w_core, WCore.Repo,
  database: Path.expand("../w_core_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :w_core, WCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RdAYVzIpMSI5bmILfH7k/rgTFlPHhknLOF/7fvbPsZYe2ly13Ufqx5R7RpDi/MBz",
  server: false

config :w_core, WCore.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :w_core, WCore.Repo,
  database: "w_core_test.sqlite3",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
