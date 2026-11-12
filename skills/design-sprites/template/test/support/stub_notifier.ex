defmodule DecisionSprite.StubNotifier do
  @moduledoc """
  Test-only Notifier adapter. Returns whatever
  `:decision_sprite, :stub_notifier_result` is set to (default :ok).
  No network, no gateway — submissions in tests never send real mail.
  """
  @behaviour DecisionSprite.Notifier

  @impl true
  def deliver(_payload) do
    Application.get_env(:decision_sprite, :stub_notifier_result, :ok)
  end
end
