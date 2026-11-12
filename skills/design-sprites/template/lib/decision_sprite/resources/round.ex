defmodule DecisionSprite.Resources.Round do
  @moduledoc """
  One round of decisions. Drafts live on its Questions; submitting freezes
  `submitted_snapshot` (question text embedded, see Content.build_snapshot/2).

  Freeze means freeze: the snapshot is NEVER cleared once set. Editing a
  submitted round withdraws the submission (status back to "open",
  `withdrawn_at` stamped) but the last snapshot stays on the round
  forever; resubmitting replaces it with the new submission's snapshot.
  `draft_revision` increments on every real write and is carried in the
  form's DOM so LiveView form-recovery can be staleness-checked.
  """
  use Ash.Resource,
    otp_app: :decision_sprite,
    domain: DecisionSprite.Domain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table("rounds")
    repo(DecisionSprite.Repo)
  end

  attributes do
    integer_primary_key(:id)
    attribute(:n, :integer, allow_nil?: false)
    attribute(:status, :string, allow_nil?: false, default: "open")
    # Verbatim ISO string (seed values must round-trip byte-exact).
    attribute(:submitted_at, :string)
    attribute(:anything_else, :string)
    attribute(:submitted_snapshot, :map)
    # Set when a submitted round is withdrawn by a real edit; nil while
    # never-submitted or currently submitted.
    attribute(:withdrawn_at, :string)
    # Monotonic counter of real draft writes; the form carries it in a
    # hidden field so a recovery event can be checked for staleness.
    attribute(:draft_revision, :integer, allow_nil?: false, default: 0)
  end

  relationships do
    has_many(:questions, DecisionSprite.Resources.Question)
  end

  identities do
    identity(:unique_n, [:n])
  end

  validations do
    validate(one_of(:status, ["open", "submitted"]), message: "status must be open or submitted")
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :n,
        :status,
        :submitted_at,
        :anything_else,
        :submitted_snapshot,
        :withdrawn_at,
        :draft_revision
      ])
    end

    update :update do
      accept([
        :status,
        :submitted_at,
        :anything_else,
        :submitted_snapshot,
        :withdrawn_at,
        :draft_revision
      ])
    end
  end
end
