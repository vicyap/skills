defmodule DecisionSpriteWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :decision_sprite

  @session_options [
    store: :cookie,
    key: "_decision_sprite_key",
    signing_salt: "decision-sprite-session",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/",
    from: :decision_sprite,
    gzip: false,
    only: DecisionSpriteWeb.static_paths()
  )

  # Phoenix / LiveView client ESM, served from the deps' own priv so the
  # release always ships the matching JS. Import map in the root layout
  # resolves the bare "phoenix" / "phoenix_live_view" specifiers.
  plug(Plug.Static,
    at: "/assets",
    from: :phoenix,
    gzip: false,
    only: ~w(phoenix.mjs)
  )

  plug(Plug.Static,
    at: "/assets",
    from: :phoenix_live_view,
    gzip: false,
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(DecisionSpriteWeb.Router)
end
