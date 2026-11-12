defmodule DecisionSpriteWeb.Auth do
  @moduledoc "Bearer-token check for the admin/API endpoints (token file is the source of truth, read per request)."
  import Plug.Conn

  def authorized?(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token == DecisionSprite.Token.current()
      _ -> false
    end
  end

  def unauthorized(conn) do
    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{"error" => "unauthorized"})
    |> halt()
  end
end
