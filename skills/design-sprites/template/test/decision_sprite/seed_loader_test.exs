defmodule DecisionSprite.SeedLoaderTest do
  use ExUnit.Case, async: false

  alias DecisionSprite.{Content, TestSupport}

  setup do
    TestSupport.wipe!()
    :ok
  end

  test "checkdown seed reproduces the backup answers byte for byte" do
    TestSupport.seed!("checkdown_state.json")
    expected = TestSupport.fixture("checkdown_answers.json")
    got = Content.answers_view()

    assert got["ok"] == expected["ok"]
    assert got["design_version"] == expected["design_version"]
    assert length(got["rounds"]) == length(expected["rounds"])

    field_count = 0

    count =
      Enum.zip(got["rounds"], expected["rounds"])
      |> Enum.reduce(field_count, fn {g, e}, acc ->
        assert g["n"] == e["n"]
        assert g["status"] == e["status"]
        assert g["submitted_at"] == e["submitted_at"]
        assert g["anything_else"] == e["anything_else"]
        assert length(g["questions"]) == length(e["questions"])

        Enum.zip(g["questions"], e["questions"])
        |> Enum.reduce(acc + 4, fn {gq, eq}, a ->
          assert gq["id"] == eq["id"]
          assert gq["prompt"] == eq["prompt"]
          assert gq["answered"] == eq["answered"]
          assert gq["answer"] == eq["answer"]
          a + 4
        end)
      end)

    # 1 round * 4 round fields + 9 questions * (id, prompt, answered, answer)
    assert count == 4 + 9 * 4
  end

  test "lab-alerts seed: open round, all drafts empty" do
    TestSupport.seed!("lab_alerts_state.json")
    view = Content.answers_view()
    assert [round] = view["rounds"]
    assert round["status"] == "open"
    assert Enum.all?(round["questions"], &(&1["answer"] == nil and &1["answered"] == false))

    state = Content.full_state()
    assert length(state["design"]["sections"]) == 4
    assert [%{"questions" => qs}] = state["rounds"]
    assert length(qs) == 9
  end

  test "zero-option questions are supported end to end" do
    {:ok, _} =
      Content.add_round(
        [%{"id" => "free", "prompt" => "Free?", "context" => nil, "options" => []}],
        false
      )

    {:ok, _} =
      Content.save_drafts(1, %{"free" => %{"other_text" => "typed freely", "comment" => ""}})

    {:ok, _} = Content.submit_round(1)

    view = Content.answers_view()
    q = hd(hd(view["rounds"])["questions"])
    assert q["answered"] == true
    assert q["answer"]["other_text"] == "typed freely"
  end
end
