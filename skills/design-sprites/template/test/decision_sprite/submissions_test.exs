defmodule DecisionSprite.SubmissionsTest do
  use ExUnit.Case, async: false

  alias DecisionSprite.{Content, Submissions, TestSupport}

  setup do
    TestSupport.wipe!()
    TestSupport.seed!("lab_alerts_state.json")
    Application.put_env(:decision_sprite, :stub_notifier_result, :ok)
    on_exit(fn -> Application.delete_env(:decision_sprite, :stub_notifier_result) end)
    :ok
  end

  test "submit → drive → sent; ack only after sent; ack is one-shot" do
    {:ok, _} = Content.save_drafts(1, %{"domain_rule" => %{"comment" => "hi"}})
    {:ok, _} = Content.submit_round(1)

    assert {:error, :not_sent} = Submissions.ack(1)

    :ok = Submissions.drive_now()
    assert Submissions.state_for(1).status == "sent"

    assert {:ok, notice} = Submissions.ack(1)
    assert notice.status == "acked"
    assert is_binary(notice.acked_at)
    assert Submissions.state_for(1).status == "acked"

    assert {:error, :not_sent} = Submissions.ack(1)
  end

  test "a failing adapter leaves the notice failed, never 'sent'" do
    Application.put_env(:decision_sprite, :stub_notifier_result, {:error, :boom})

    {:ok, _} = Content.submit_round(1)
    :ok = Submissions.drive_now()

    state = Submissions.state_for(1)
    assert state.status == "failed"
    assert {:error, :not_sent} = Submissions.ack(1)
  end

  test "mail gateway failure is an honest error, never a pretend send" do
    # Point the gateway at a dead local port: the POST must come back as
    # an error tuple — the submission stays UNDELIVERED, visibly.
    Application.put_env(:decision_sprite, :mail_gateway_url, "http://127.0.0.1:1/emails")
    on_exit(fn -> Application.delete_env(:decision_sprite, :mail_gateway_url) end)

    payload = %{"sprite" => "test", "round" => 1, "submitted_at" => "t", "notice_id" => 1}
    assert {:error, _} = DecisionSprite.Notifier.MailGateway.deliver(payload)
  end
end
