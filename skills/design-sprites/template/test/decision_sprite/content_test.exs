defmodule DecisionSprite.ContentTest do
  use ExUnit.Case, async: false

  alias DecisionSprite.{Content, TestSupport}
  alias DecisionSprite.Resources.SubmissionNotice
  alias DecisionSprite.Domain

  setup do
    TestSupport.wipe!()
    TestSupport.seed!("lab_alerts_state.json")
    :ok
  end

  defp notices do
    SubmissionNotice |> Ash.read!(domain: Domain) |> Enum.sort_by(& &1.id)
  end

  test "autosave identical after normalization writes nothing" do
    {:ok, %{changed: true}} =
      Content.save_drafts(1, %{"domain_rule" => %{"comment" => "hello world"}})

    rev = Content.latest_round().draft_revision

    # Same words modulo surrounding whitespace and a trailing CRLF →
    # the write path's cast makes them identical → no write, no bump.
    # (Internal line endings stay verbatim — only the edges normalize.)
    {:ok, %{changed: false}} =
      Content.save_drafts(1, %{"domain_rule" => %{"comment" => "  hello world\r\n"}})

    assert Content.latest_round().draft_revision == rev
  end

  test "targeted change writes only the targeted field" do
    {:ok, _} =
      Content.save_drafts(1, %{
        "domain_rule" => %{"choice" => "split_review_ops", "comment" => "first"}
      })

    # A stale form echo carries a DIFFERENT choice, but the event only
    # targeted the comment field — the choice must not move.
    {:ok, %{changed: true}} =
      Content.save_drafts(
        1,
        %{"domain_rule" => %{"choice" => "other", "comment" => "second"}},
        :unchanged,
        target: {:field, "domain_rule", :comment}
      )

    q =
      Content.answers_view()["rounds"]
      |> hd()
      |> Map.get("questions")
      |> Enum.find(&(&1["id"] == "domain_rule"))

    assert q["answer"]["choice"] == "split_review_ops"
    assert q["answer"]["comment"] == "second"
  end

  test "clearing a comment persists (targeted event)" do
    {:ok, _} = Content.save_drafts(1, %{"domain_rule" => %{"comment" => "to be cleared"}})

    # Regression: a cleared field casts to nil, and a nil cast must still
    # be written. A comprehension filter step `casted = cast_text(raw)`
    # evaluates to nil for a clear, which is falsy, so the old code
    # silently dropped every clear and the stored text came back on the
    # next render.
    {:ok, %{changed: true}} =
      Content.save_drafts(1, %{"domain_rule" => %{"comment" => ""}}, :unchanged,
        target: {:field, "domain_rule", :comment}
      )

    q =
      Content.answers_view()["rounds"]
      |> hd()
      |> Map.get("questions")
      |> Enum.find(&(&1["id"] == "domain_rule"))

    assert q["answer"] == nil
  end

  test "clearing fields persists in a full-form save (beacon/submit shape)" do
    {:ok, _} =
      Content.save_drafts(1, %{
        "domain_rule" => %{"choice" => "other", "other_text" => "mine", "comment" => "note"}
      })

    {:ok, %{changed: true}} =
      Content.save_drafts(1, %{
        "domain_rule" => %{"choice" => "other", "other_text" => "", "comment" => ""}
      })

    q =
      Content.answers_view()["rounds"]
      |> hd()
      |> Map.get("questions")
      |> Enum.find(&(&1["id"] == "domain_rule"))

    assert q["answer"]["choice"] == "other"
    assert q["answer"]["other_text"] == ""
    assert q["answer"]["comment"] == ""
  end

  test "clearing an answer on a submitted round withdraws the submission" do
    {:ok, _} = Content.save_drafts(1, %{"domain_rule" => %{"comment" => "x"}})
    {:ok, %{already: false}} = Content.submit_round(1)
    assert Content.latest_round().status == "submitted"

    {:ok, %{changed: true, withdrawn: true}} =
      Content.save_drafts(1, %{"domain_rule" => %{"comment" => ""}}, :unchanged,
        target: {:field, "domain_rule", :comment}
      )

    assert Content.latest_round().status == "open"
  end

  test "submit writes an outbox notice in the same step; resubmit is a no-op" do
    {:ok, _} = Content.save_drafts(1, %{"domain_rule" => %{"comment" => "x"}})
    {:ok, %{already: false}} = Content.submit_round(1)

    assert [notice] = notices()
    assert notice.round_n == 1
    assert notice.status in ["pending", "sent"]
    assert is_binary(notice.submitted_at)

    # The notice payload carries ids/timestamps only — no answer content.
    payload = DecisionSprite.Notifier.payload(notice)
    assert Enum.sort(Map.keys(payload)) == ["notice_id", "round", "sprite", "submitted_at"]

    {:ok, %{already: true}} = Content.submit_round(1)
    assert length(notices()) == 1
  end

  test "non-latest rounds are sealed for saves and submits" do
    {:ok, _} = Content.submit_round(1)

    {:ok, _round2} =
      Content.add_round([%{"id" => "nq", "prompt" => "Next?", "options" => []}], false)

    assert {:error, :sealed_round} =
             Content.save_drafts(1, %{"domain_rule" => %{"comment" => "late edit"}})

    assert {:error, :sealed_round} = Content.submit_round(1)
  end

  test "round 1 answers are byte-identical after round 2 is added" do
    TestSupport.wipe!()
    TestSupport.seed!("checkdown_state.json")
    before = Jason.encode!(hd(Content.answers_view()["rounds"]))

    {:ok, _} =
      Content.add_round([%{"id" => "nq", "prompt" => "Next?", "options" => []}], false)

    after_view = Jason.encode!(hd(Content.answers_view()["rounds"]))
    assert after_view == before
  end

  test "add_round with replace_open never destroys a snapshotted round" do
    {:ok, _} = Content.save_drafts(1, %{"domain_rule" => %{"comment" => "keep me"}})
    {:ok, _} = Content.submit_round(1)
    # Real edit withdraws → round 1 open again, snapshot intact.
    {:ok, %{withdrawn: true}} =
      Content.save_drafts(1, %{"domain_rule" => %{"comment" => "keep me, edited"}})

    assert {:error, :open_round_exists} =
             Content.add_round([%{"id" => "nq", "prompt" => "Next?", "options" => []}], true)

    round = Content.latest_round()
    assert round.n == 1
    assert is_map(round.submitted_snapshot)
  end

  test "seed loader refuses to drop a snapshot unless forced" do
    TestSupport.wipe!()
    TestSupport.seed!("checkdown_state.json")
    lab = TestSupport.fixture("lab_alerts_state.json")

    assert {:error, {:would_drop_snapshot, [1]}} = DecisionSprite.SeedLoader.load(lab)
    # Untouched:
    assert Content.latest_round().status == "submitted"

    assert :ok = DecisionSprite.SeedLoader.load(lab, force: true)
    assert Content.latest_round().status == "open"
  end
end
