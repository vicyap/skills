defmodule DecisionSpriteWeb.QuestionsLiveTest do
  use DecisionSpriteWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DecisionSprite.{Content, TestSupport}

  setup do
    TestSupport.seed!("lab_alerts_state.json")
    :ok
  end

  test "renders the open round: 9 questions, 9 Other radios, 9 comment fields", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/questions")

    assert html =~ "Round 1"
    assert html =~ "Submit to Muse"
    # one submit button only, no per-question save buttons
    assert Regex.scan(~r/Submit to Muse/, html) |> length() == 1

    for q <- hd(Content.full_state()["rounds"])["questions"] do
      escaped = q["prompt"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ escaped
    end

    assert Regex.scan(~r/value="other"/, html) |> length() == 9
    assert Regex.scan(~r/\[comment\]/, html) |> length() == 9
  end

  test "autosave: a change event persists the draft server-side", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/questions")

    html =
      render_change(view, "save", %{
        "questions" => %{
          "domain_rule" => %{
            "choice" => "split_review_ops",
            "other_text" => "",
            "comment" => "autosave marker comment"
          }
        },
        "anything_else" => ""
      })

    assert html =~ "draft saved"

    # Draft is in the DB, visible verbatim through the admin view.
    view_answers = Content.answers_view()
    round = hd(view_answers["rounds"])
    q = Enum.find(round["questions"], &(&1["id"] == "domain_rule"))
    assert q["answered"] == true
    assert q["answer"]["choice"] == "split_review_ops"
    assert q["answer"]["choice_label"] =~ "Split it"
    assert q["answer"]["comment"] == "autosave marker comment"

    # And it survives a fresh LiveView mount (i.e. it is really persisted).
    {:ok, _view2, html2} = live(conn, "/questions")
    assert html2 =~ "autosave marker comment"
  end

  test "submit freezes a snapshot; editing afterwards withdraws it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/questions")

    marker_other = "ZZ marker other text — punctuation: yes! (really)"
    marker_comment = "line one\nline two, with punctuation; and 'quotes'"

    render_change(view, "save", %{
      "questions" => %{
        "domain_rule" => %{
          "choice" => "other",
          "other_text" => marker_other,
          "comment" => marker_comment
        }
      },
      "anything_else" => "anything marker"
    })

    html =
      render_submit(view, "submit", %{"questions" => %{}, "anything_else" => "anything marker"})

    assert html =~ "submitted ·"

    view_answers = Content.answers_view()
    round = hd(view_answers["rounds"])
    assert round["status"] == "submitted"
    assert is_binary(round["submitted_at"])
    assert round["anything_else"] == "anything marker"

    q = Enum.find(round["questions"], &(&1["id"] == "domain_rule"))
    assert q["answer"]["choice"] == "other"
    assert q["answer"]["choice_label"] == "Other (specify)"
    assert q["answer"]["other_text"] == marker_other
    assert q["answer"]["comment"] == marker_comment

    # The frozen snapshot embeds the question text, not just the answer.
    submitted_round = Content.latest_round()
    snap_entry = submitted_round.submitted_snapshot["questions"]["domain_rule"]
    assert snap_entry["prompt"] =~ "split engineering review"
    assert snap_entry["answer"]["comment"] == marker_comment
    snapshot_before = submitted_round.submitted_snapshot

    # Edit after submit → withdrawal: status open, drafts kept — and
    # FREEZE MEANS FREEZE: the snapshot is NOT cleared.
    {:ok, view2, _} = live(conn, "/questions")

    html2 =
      render_change(view2, "save", %{
        "questions" => %{
          "domain_rule" => %{
            "choice" => "other",
            "other_text" => marker_other,
            "comment" => marker_comment <> " edited"
          }
        },
        "anything_else" => "anything marker"
      })

    assert html2 =~ "submission withdrawn"

    round2 = hd(Content.answers_view()["rounds"])
    assert round2["status"] == "open"
    assert round2["submitted_at"] == nil
    # The withdrawn round still reports its frozen snapshot verbatim.
    assert is_binary(round2["withdrawn_since"])

    assert round2["last_snapshot"]["questions"]
           |> Enum.find(&(&1["id"] == "domain_rule"))
           |> Map.get("answer")
           |> Map.get("comment") == marker_comment

    q2 = Enum.find(round2["questions"], &(&1["id"] == "domain_rule"))
    assert q2["answer"]["comment"] == marker_comment <> " edited"
    assert q2["answer"]["other_text"] == marker_other

    db_round = Content.latest_round()
    assert db_round.submitted_snapshot == snapshot_before
  end

  test "disconnected render says connecting and disables Submit", %{conn: conn} do
    conn = get(conn, "/questions")
    html = html_response(conn, 200)
    assert html =~ "connecting"
    assert html =~ ~s(disabled)
  end

  test "an identical change after submit does NOT withdraw", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/questions")

    answers = %{
      "questions" => %{
        "domain_rule" => %{
          "choice" => "split_review_ops",
          "other_text" => "",
          "comment" => "same words"
        }
      },
      "anything_else" => ""
    }

    render_change(view, "save", answers)
    render_submit(view, "submit", %{"questions" => %{}, "anything_else" => ""})
    revision_before = Content.latest_round().draft_revision

    {:ok, view2, _} = live(conn, "/questions")
    html = render_change(view2, "save", answers)

    refute html =~ "withdrawn"
    round = Content.latest_round()
    assert round.status == "submitted"
    assert round.draft_revision == revision_before
  end

  test "form recovery never withdraws and never writes a submitted round", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/questions")

    render_change(view, "save", %{
      "questions" => %{
        "domain_rule" => %{"choice" => "split_review_ops", "other_text" => "", "comment" => "v1"}
      },
      "anything_else" => ""
    })

    render_submit(view, "submit", %{"questions" => %{}, "anything_else" => ""})
    revision = Content.latest_round().draft_revision

    {:ok, view2, _} = live(conn, "/questions")

    html =
      render_change(view2, "recover_draft", %{
        "questions" => %{
          "domain_rule" => %{
            "choice" => "other",
            "other_text" => "recovered",
            "comment" => "changed"
          }
        },
        "anything_else" => "",
        "revision" => Integer.to_string(revision)
      })

    # Not applied — the conflict banner offers an explicit apply instead.
    assert html =~ "NOT applied"
    round = Content.latest_round()
    assert round.status == "submitted"

    q =
      Enum.find(
        Content.answers_view()["rounds"] |> hd() |> Map.get("questions"),
        &(&1["id"] == "domain_rule")
      )

    assert q["answer"]["comment"] == "v1"
  end

  test "empty state when there are no rounds", %{conn: conn} do
    Content.wipe!()
    {:ok, _view, html} = live(conn, "/questions")
    assert html =~ "No open decisions right now"
    assert html =~ "with Muse"
  end
end
