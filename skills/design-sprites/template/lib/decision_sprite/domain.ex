defmodule DecisionSprite.Domain do
  use Ash.Domain

  resources do
    resource(DecisionSprite.Resources.DesignDoc)
    resource(DecisionSprite.Resources.Round)
    resource(DecisionSprite.Resources.Question)
    resource(DecisionSprite.Resources.SubmissionNotice)
  end
end
