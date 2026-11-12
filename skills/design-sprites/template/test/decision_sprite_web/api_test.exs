defmodule DecisionSpriteWeb.ApiTest do
  use DecisionSpriteWeb.ConnCase

  alias DecisionSprite.TestSupport

  test "health does a real round trip", %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")
    conn = get(conn, "/health")

    assert %{
             "ok" => true,
             "rounds" => 1,
             "design_version" => 1,
             "template_version" => "0.2.0"
           } = json_response(conn, 200)
  end

  test "ack: Bearer-gated, 404 without a notice, 200 once sent", %{conn: _conn} do
    TestSupport.seed!("lab_alerts_state.json")

    assert json_response(post(build_conn(), "/admin/ack", %{"round" => 1}), 401) ==
             %{"error" => "unauthorized"}

    auth = fn c -> TestSupport.authed(c) end

    conn = auth.(build_conn()) |> post("/admin/ack", %{"round" => 1})
    assert json_response(conn, 404) == %{"error" => "no submission notice for that round"}

    {:ok, _} = DecisionSprite.Content.submit_round(1)
    :ok = DecisionSprite.Submissions.drive_now()

    conn = auth.(build_conn()) |> post("/admin/ack", %{"round" => 1})
    assert json_response(conn, 200) == %{"ok" => true}
    assert DecisionSprite.Submissions.state_for(1).status == "acked"
  end

  test "reset that would drop a submitted snapshot is refused with 409", %{conn: _conn} do
    TestSupport.seed!("checkdown_state.json")
    lab = TestSupport.fixture("lab_alerts_state.json")
    auth = fn c -> TestSupport.authed(c) end

    conn = auth.(build_conn()) |> post("/api/reset", %{"state" => lab})
    assert %{"error" => "would_drop_snapshot", "rounds" => [1]} = json_response(conn, 409)

    conn = auth.(build_conn()) |> post("/api/reset", %{"state" => lab, "force" => true})
    assert json_response(conn, 200) == %{"ok" => true}
  end

  test "draft beacon saves through the same path the socket uses", %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")

    page = get(conn, "/questions")
    html = html_response(page, 200)
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)

    conn =
      page
      |> recycle()
      |> post("/api/draft", %{
        "_csrf_token" => token,
        "questions" => %{"domain_rule" => %{"comment" => "beacon marker"}},
        "anything_else" => ""
      })

    assert conn.status == 204

    q =
      DecisionSprite.Content.answers_view()["rounds"]
      |> hd()
      |> Map.get("questions")
      |> Enum.find(&(&1["id"] == "domain_rule"))

    assert q["answer"]["comment"] == "beacon marker"
  end

  test "admin endpoints reject missing/bad tokens", %{conn: conn} do
    assert json_response(get(conn, "/admin/answers"), 401) == %{"error" => "unauthorized"}
    assert json_response(get(conn, "/api/state"), 401) == %{"error" => "unauthorized"}

    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong")
      |> get("/admin/answers")

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end

  test "answers + state shapes for the lab-alerts seed", %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")

    conn = TestSupport.authed(conn)
    body = json_response(get(conn, "/admin/answers"), 200)
    assert body["ok"] == true
    assert body["design_version"] == 1
    assert [round] = body["rounds"]
    assert round["n"] == 1
    assert round["status"] == "open"
    assert round["submitted_at"] == nil
    assert length(round["questions"]) == 9
    assert Enum.all?(round["questions"], &(&1["answered"] == false and &1["answer"] == nil))

    state = json_response(get(build_conn() |> TestSupport.authed(), "/api/state"), 200)
    assert state["design"]["version"] == 1
    assert length(state["design"]["sections"]) == 4
    assert [%{"questions" => qs}] = state["rounds"]
    assert length(qs) == 9
    assert hd(qs)["context"] != nil
    assert hd(qs)["options"] |> length() == 4
  end

  test "design page renders sections and the app title", %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")
    conn = get(conn, "/")
    html = html_response(conn, 200)
    assert html =~ "What this is"
    assert html =~ "Where things stand"
    assert html =~ "Proposed quick fix"
    assert html =~ "What this round decides"
    assert html =~ "Decisions with Muse"
    assert html =~ "/questions"
  end

  test "rounds: 409 while a round is open, allowed after submit, design bumps version",
       %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")
    auth = fn c -> TestSupport.authed(c) end

    conn =
      auth.(build_conn())
      |> post("/api/rounds", %{"questions" => [%{"id" => "x", "prompt" => "X?", "options" => []}]})

    assert json_response(conn, 409) == %{"error" => "an open round exists"}

    # Submit round 1 through the context (same path the LiveView uses),
    # then posting round 2 is allowed.
    {:ok, _} = DecisionSprite.Content.submit_round(1)

    conn =
      auth.(build_conn())
      |> post("/api/rounds", %{
        "questions" => [
          %{
            "id" => "free_text_q",
            "prompt" => "Say anything?",
            "context" => "no options at all",
            "options" => []
          }
        ]
      })

    assert json_response(conn, 200) == %{"ok" => true}

    state = json_response(get(auth.(build_conn()), "/api/state"), 200)
    assert length(state["rounds"]) == 2
    assert Enum.at(state["rounds"], 1)["n"] == 2

    conn =
      auth.(build_conn())
      |> post("/api/design", %{"sections" => [%{"heading" => "New", "body" => "Body"}]})

    assert json_response(conn, 200) == %{"ok" => true}
    assert DecisionSprite.Content.design_version() == 2
  end

  test "reset replaces all content", %{conn: conn} do
    TestSupport.seed!("lab_alerts_state.json")
    checkdown = TestSupport.fixture("checkdown_state.json")

    conn =
      TestSupport.authed(build_conn())
      |> post("/api/reset", %{"state" => checkdown})

    assert json_response(conn, 200) == %{"ok" => true}
    assert DecisionSprite.Content.design_version() == 1
    assert DecisionSprite.Content.rounds_count() == 1
    _ = conn
  end
end
