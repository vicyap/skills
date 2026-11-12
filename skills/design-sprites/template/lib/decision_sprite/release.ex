defmodule DecisionSprite.Release do
  @moduledoc """
  Release tasks invoked from scripts/run.sh before the server starts:
  `bin/decision_sprite eval "DecisionSprite.Release.migrate()"`.
  The DDL is the idempotent Store schema (house pattern), so migrate and
  boot can never disagree about the schema.
  """

  def migrate do
    {:ok, _} = Application.ensure_all_started(:decision_sprite)
    :ok = DecisionSprite.Store.ensure_schema!()
    DecisionSprite.Observe.emit("app.migrate", "succeeded", %{})
    :ok
  end
end
