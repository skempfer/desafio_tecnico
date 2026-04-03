import Config

config :w_core, WCore.Repo,
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :w_core, WCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "YeFv7I1pLsjrDWnkcOIPFEfmKF+W7S8pw0YJymbEmXmshGooz8L5afOI1efRdGg4",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:w_core, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:w_core, ~w(--watch)]}
  ]

config :w_core, WCoreWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*\.po$",
      ~r"lib/w_core_web/router\.ex$",
      ~r"lib/w_core_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

config :w_core, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
