import Config

if System.get_env("PHX_SERVER") do
  config :w_core, WCoreWeb.Endpoint, server: true
end

config :w_core, WCoreWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

database_path = System.get_env("DATABASE_PATH", "./data/w_core.sqlite3")

config :w_core, WCore.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :w_core, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :w_core, WCoreWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
