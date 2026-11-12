defmodule DecisionSprite.Resources.Question do
  @moduledoc """
  One question in a round. The draft answer fields (choice, choice_label,
  other_text, comment) autosave on every LiveView change event; they are
  copied verbatim into the round's snapshot on submit.
  """
  use Ash.Resource,
    otp_app: :decision_sprite,
    domain: DecisionSprite.Domain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table("questions")
    repo(DecisionSprite.Repo)
  end

  attributes do
    integer_primary_key(:id)
    attribute(:round_id, :integer)
    attribute(:qid, :string, allow_nil?: false)
    attribute(:prompt, :string, allow_nil?: false)
    attribute(:context, :string)
    attribute(:options, {:array, :map}, default: [])
    attribute(:position, :integer, allow_nil?: false, default: 0)
    # Draft answer (nullable; an untouched question has all four nil).
    attribute(:choice, :string)
    attribute(:choice_label, :string)
    attribute(:other_text, :string)
    attribute(:comment, :string)
  end

  relationships do
    belongs_to(:round, DecisionSprite.Resources.Round,
      attribute_writable?: true,
      define_attribute?: false
    )
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :round_id,
        :qid,
        :prompt,
        :context,
        :options,
        :position,
        :choice,
        :choice_label,
        :other_text,
        :comment
      ])
    end

    update :save_draft do
      accept([:choice, :choice_label, :other_text, :comment])
    end
  end
end
