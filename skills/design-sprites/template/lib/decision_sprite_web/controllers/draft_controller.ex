defmodule DecisionSpriteWeb.DraftController do
  @moduledoc """
  The pagehide safety net: the DraftFlush hook fires
  `navigator.sendBeacon("/api/draft", FormData)` when the page is hidden
  or closed, so the last edits inside the debounce window still reach
  the server when the LiveView socket is already gone. It runs the
  EXACT same normalized, idempotent Content.save_drafts as the socket
  path — one save logic, two transports. CSRF is enforced by the
  browser pipeline (the form carries a _csrf_token field).
  """
  use DecisionSpriteWeb, :controller

  alias DecisionSprite.Content

  def save(conn, params) do
    case Content.latest_round() do
      nil ->
        send_resp(conn, 204, "")

      round ->
        anything_else =
          case Map.fetch(params, "anything_else") do
            {:ok, v} -> v
            :error -> :unchanged
          end

        Content.save_drafts(round.n, params["questions"] || %{}, anything_else)
        send_resp(conn, 204, "")
    end
  end
end
