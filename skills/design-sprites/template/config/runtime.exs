import Config

if config_env() == :prod do
  database_path = System.get_env("DATABASE_PATH")

  data_dir =
    System.get_env("DATA_DIR") ||
      (database_path && Path.dirname(database_path)) ||
      "/data"

  config :decision_sprite, :data_dir, data_dir

  config :decision_sprite, DecisionSprite.Repo,
    database: database_path || Path.join(data_dir, "app.db"),
    journal_mode: :wal,
    pool_size: 5

  if token_file = System.get_env("ADMIN_TOKEN_FILE") do
    config :decision_sprite, :admin_token_file, token_file
  end

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      :crypto.strong_rand_bytes(64) |> Base.encode64()

  # The deployment's real public host, set per sprite at deploy time
  # (run.sh carries a __SPRITE_HOST__ placeholder the deploy replaces).
  # An unset/unreplaced value falls back to "localhost" for URL
  # generation only — origin CHECKING below does not depend on it.
  phx_host =
    case System.get_env("PHX_HOST") do
      h when h in [nil, "", "__SPRITE_HOST__"] -> "localhost"
      h -> h
    end

  config :decision_sprite, DecisionSpriteWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT") || "8080")],
    # Phoenix.Endpoint docs: check_origin defaults to true against the
    # :url host. Sprites serve from *.sprites.app origins, so the allowed
    # origins are stated explicitly (wildcards are documented) instead of
    # checking against "localhost" (the original fleet-wide bug) or
    # disabling the check outright.
    check_origin: ["https://*.sprites.app", "//localhost"],
    url: [host: phx_host, port: 443, scheme: "https"],
    secret_key_base: secret_key_base,
    server: System.get_env("PHX_SERVER") == "true"

  # R2 submit delivery: the Notifier adapter is config, not code.
  # SUBMIT_NOTIFIER = webhook | mail_gateway | (unset → Log, which
  # honestly reports undelivered).
  notifier =
    case System.get_env("SUBMIT_NOTIFIER") do
      "webhook" -> DecisionSprite.Notifier.Webhook
      "mail_gateway" -> DecisionSprite.Notifier.MailGateway
      _ -> DecisionSprite.Notifier.Log
    end

  config :decision_sprite, :notifier, notifier
  config :decision_sprite, :notify_url, System.get_env("SUBMIT_NOTIFY_URL")
  config :decision_sprite, :notify_token, System.get_env("SUBMIT_NOTIFY_TOKEN")
  config :decision_sprite, :sprite_name, System.get_env("SPRITE_NAME")
  # Mail gateway (SUBMIT_NOTIFIER=mail_gateway): the /emails URL is
  # normally DISCOVERED from the sprite's gateway list at first send
  # (conn:resend); SUBMIT_MAIL_GATEWAY_URL pins it explicitly.
  config :decision_sprite, :mail_gateway_url, System.get_env("SUBMIT_MAIL_GATEWAY_URL")
  config :decision_sprite, :mail_from, System.get_env("SUBMIT_MAIL_FROM")
  config :decision_sprite, :mail_to, System.get_env("SUBMIT_MAIL_TO")

  config :logger, level: :info
end
