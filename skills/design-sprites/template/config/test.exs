import Config

test_data =
  Path.join(System.tmp_dir!(), "decision_sprite_test_#{:erlang.unique_integer([:positive])}")

File.mkdir_p!(test_data)
config :decision_sprite, :data_dir, test_data

config :decision_sprite, DecisionSprite.Repo,
  database: Path.join(test_data, "app.db"),
  journal_mode: :wal,
  pool_size: 5

config :decision_sprite, DecisionSpriteWeb.Endpoint,
  http: [port: 4002],
  secret_key_base: "test-only-secret-key-base-0123456789abcdef0123456789abcdef0123456789abcde",
  server: false

# Submissions in tests deliver through a controllable stub, never the
# network. Individual tests override :stub_notifier_result as needed.
config :decision_sprite, :notifier, DecisionSprite.StubNotifier

config :logger, level: :warning
