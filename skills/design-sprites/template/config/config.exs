import Config

config :decision_sprite, ash_domains: [DecisionSprite.Domain]
config :decision_sprite, ecto_repos: [DecisionSprite.Repo]
config :ash, default_string_length_count: :codepoints

config :decision_sprite, DecisionSpriteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DecisionSpriteWeb.ErrorHTML, json: DecisionSpriteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DecisionSprite.PubSub,
  live_view: [signing_salt: "decision-sprite-live"],
  # Never log answer content: filter every answer-bearing parameter in
  # ALL environments (observability checklist, section 3).
  filter_parameters: [
    "password",
    "token",
    "secret",
    "choice",
    "choice_label",
    "other_text",
    "comment",
    "answer",
    "anything_else"
  ]

config :phoenix, :json_library, Jason

config :logger, :console, format: "$message\n", metadata: []

import_config "#{config_env()}.exs"
