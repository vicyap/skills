defmodule DecisionSprite.Resources.SubmissionNotice do
  @moduledoc """
  The outbox row for one submission (requirement R2: Muse RECEIVES the
  answers at submit time). Written in the SAME transaction as the freeze;
  a worker then delivers it through the configured Notifier adapter and
  tracks delivery here:

    pending -> sent -> acked        (acked only by Muse's explicit ack)
    pending -> failed (retried with backoff, status returns to pending)

  Carries ids and timestamps only — never answer content.
  """
  use Ash.Resource,
    otp_app: :decision_sprite,
    domain: DecisionSprite.Domain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table("submission_notices")
    repo(DecisionSprite.Repo)
  end

  attributes do
    integer_primary_key(:id)
    attribute(:round_n, :integer, allow_nil?: false)
    attribute(:submitted_at, :string)
    attribute(:status, :string, allow_nil?: false, default: "pending")
    attribute(:attempts, :integer, allow_nil?: false, default: 0)
    attribute(:last_error, :string)
    attribute(:sent_at, :string)
    attribute(:acked_at, :string)
    attribute(:created_at, :string)
    attribute(:updated_at, :string)
  end

  validations do
    validate(one_of(:status, ["pending", "sent", "failed", "acked"]),
      message: "status must be pending, sent, failed or acked"
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :round_n,
        :submitted_at,
        :status,
        :attempts,
        :last_error,
        :sent_at,
        :acked_at,
        :created_at,
        :updated_at
      ])
    end

    update :update do
      accept([:status, :attempts, :last_error, :sent_at, :acked_at, :updated_at])
    end
  end
end
