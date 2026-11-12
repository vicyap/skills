defmodule DecisionSpriteWeb.Router do
  use DecisionSpriteWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {DecisionSpriteWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", DecisionSpriteWeb do
    pipe_through(:browser)

    get("/", PageController, :design)
    live("/questions", QuestionsLive)
    # sendBeacon draft flush (pagehide) — browser pipeline for session+CSRF.
    post("/api/draft", DraftController, :save)
  end

  scope "/", DecisionSpriteWeb do
    pipe_through(:api)

    get("/health", ApiController, :health)
    get("/admin/answers", ApiController, :answers)
    get("/api/state", ApiController, :state)
    post("/api/rounds", ApiController, :create_round)
    post("/api/design", ApiController, :update_design)
    post("/api/reset", ApiController, :reset)
    post("/api/seed", ApiController, :reset)
    # Muse's explicit ack that it read a submitted round (R2).
    post("/admin/ack", ApiController, :ack)
  end
end
