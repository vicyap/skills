import Config

dev_data = Path.expand("../dev-data", __DIR__)
config :decision_sprite, :data_dir, dev_data

config :decision_sprite, DecisionSprite.Repo,
  database: Path.join(dev_data, "app.db"),
  journal_mode: :wal,
  pool_size: 5,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :decision_sprite, DecisionSpriteWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || "4000")],
  secret_key_base: "dev-only-secret-key-base-0123456789abcdef0123456789abcdef0123456789abcdef",
  server: true,
  debug_errors: true,
  check_origin: false,
  code_reloader: false

config :logger, :console, format: "$message\n", level: :info
