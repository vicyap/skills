defmodule DecisionSpriteWeb.Layouts do
  @moduledoc "Root and app layouts: the Impeccable 'Observability' document shell."
  use DecisionSpriteWeb, :html

  embed_templates("layouts/*")

  def title(assigns) do
    assigns[:page_title] || DecisionSprite.Content.app_title()
  end
end
