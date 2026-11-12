defmodule DecisionSpriteWeb.AssetRegressionTest do
  @moduledoc """
  Regression tests for the TWO bug classes that silently killed the
  fleet's forms on 2026-11-11 (see ~/workspace/design/decision-sprite-template.md):

  1. Phoenix 1.8 ships `phoenix.mjs`; the template referenced
     `phoenix.esm.js` → 404 → the LiveView module import failed.
  2. The bootstrap guarded on `window.LiveSocket`, a global the ES
     module build never sets → the socket never connected.

  A template release must fail its own tests if either regresses.
  """
  use DecisionSpriteWeb.ConnCase

  alias DecisionSprite.TestSupport

  setup do
    TestSupport.seed!("lab_alerts_state.json")
    :ok
  end

  test "the page's importmap points at assets that actually serve", %{conn: conn} do
    conn = get(conn, "/questions")
    html = html_response(conn, 200)

    assert html =~ "/assets/phoenix.mjs"
    assert html =~ "/assets/phoenix_live_view.esm.js"
    refute html =~ "phoenix.esm.js"

    for asset <- ["phoenix.mjs", "phoenix_live_view.esm.js"] do
      c = get(build_conn(), "/assets/" <> asset)
      assert c.status == 200, "expected /assets/#{asset} to serve, got #{c.status}"
      assert byte_size(c.resp_body) > 1_000
    end

    # The app's own module script is referenced as /app.js in the layout.
    c = get(build_conn(), "/app.js")
    assert c.status == 200
    assert c.resp_body =~ "longPollFallbackMs"
  end

  test "app.js bootstraps from module imports, never a window.LiveSocket guard" do
    app_js =
      :decision_sprite
      |> Application.app_dir("priv/static/app.js")
      |> File.read!()

    assert app_js =~ ~s(import { LiveSocket } from "phoenix_live_view")
    assert app_js =~ "liveSocket.connect()"
    # The hand-build's fatal guard. (Assignment `window.liveSocket =` is
    # fine; looking the class UP on window is the bug.)
    refute app_js =~ "window.LiveSocket"
    # Documented transport fallback for sprite/Safari websocket kills.
    assert app_js =~ "longPollFallbackMs: 2500"
  end
end
