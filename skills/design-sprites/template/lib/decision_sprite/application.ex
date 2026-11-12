defmodule DecisionSprite.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DecisionSprite.Repo,
      {Phoenix.PubSub, name: DecisionSprite.PubSub},
      DecisionSprite.Submissions,
      DecisionSpriteWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DecisionSprite.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      :ok = DecisionSprite.Store.ensure_schema!()
      :ok = DecisionSprite.Token.ensure!()
      :ok = DecisionSprite.SeedLoader.seed_if_empty!()
      DecisionSprite.Observe.emit("app.boot", "succeeded", %{})
      {:ok, pid}
    end
  end
end
