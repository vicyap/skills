defmodule DecisionSprite.Resources.DesignDoc do
  @moduledoc "The design document: versioned sections rendered on GET /. Singleton in practice (the loader keeps exactly one row)."
  use Ash.Resource,
    otp_app: :decision_sprite,
    domain: DecisionSprite.Domain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table("design_docs")
    repo(DecisionSprite.Repo)
  end

  attributes do
    integer_primary_key(:id)
    attribute(:version, :integer, allow_nil?: false, default: 0)
    # Kept as the verbatim ISO string from the seed so state round-trips byte-exact.
    attribute(:updated_at, :string, allow_nil?: false, default: "")
    attribute(:title, :string)
    attribute(:sections, {:array, :map}, default: [])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:version, :updated_at, :title, :sections])
    end

    update :update do
      accept([:version, :updated_at, :title, :sections])
    end
  end
end
