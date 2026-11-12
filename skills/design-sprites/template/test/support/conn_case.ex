defmodule DecisionSpriteWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import DecisionSpriteWeb.ConnCase

      @endpoint DecisionSpriteWeb.Endpoint
    end
  end

  setup _tags do
    DecisionSprite.TestSupport.wipe!()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

defmodule DecisionSprite.TestSupport do
  @moduledoc "Reset the database between tests (no sandbox: AshSqlite test DB is a scratch file)."

  def wipe! do
    DecisionSprite.Content.wipe!()
    :ok
  end

  def fixture(name) do
    Path.expand("../fixtures/#{name}", __DIR__)
    |> File.read!()
    |> Jason.decode!()
  end

  def seed!(name) do
    state = fixture(name)
    DecisionSprite.SeedLoader.load(state)
    state
  end

  def token, do: DecisionSprite.Token.current()

  def authed(conn) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token())
  end
end
