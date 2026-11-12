defmodule DecisionSpriteWeb.ApiController do
  use DecisionSpriteWeb, :controller

  alias DecisionSprite.{Content, Observe, SeedLoader}
  alias DecisionSpriteWeb.Auth

  def health(conn, _params) do
    # Real DB write+read probe round trip (not a count alone).
    if DecisionSprite.Store.health_probe() do
      json(conn, %{
        "ok" => true,
        "rounds" => Content.rounds_count(),
        "design_version" => Content.design_version(),
        "template_version" => Content.template_version()
      })
    else
      conn |> put_status(503) |> json(%{"ok" => false})
    end
  end

  @doc """
  Muse's explicit ack: "I have read this round." Only a sent notice can
  be acked — a fetch or poll can never mark a submission picked up.
  """
  def ack(conn, params) do
    if Auth.authorized?(conn) do
      case params["round"] do
        n when is_integer(n) ->
          case DecisionSprite.Submissions.ack(n) do
            {:ok, _notice} ->
              json(conn, %{"ok" => true})

            {:error, :no_notice} ->
              conn |> put_status(404) |> json(%{"error" => "no submission notice for that round"})

            {:error, :not_sent} ->
              conn |> put_status(409) |> json(%{"error" => "submission notice not sent yet"})

            {:error, _} ->
              conn |> put_status(422) |> json(%{"error" => "ack failed"})
          end

        _ ->
          conn |> put_status(422) |> json(%{"error" => "round is required"})
      end
    else
      Auth.unauthorized(conn)
    end
  end

  def answers(conn, _params) do
    if Auth.authorized?(conn) do
      view = Content.answers_view()
      Observe.emit("admin.answers_viewed", "succeeded", %{rounds: length(view["rounds"])})
      json(conn, view)
    else
      Auth.unauthorized(conn)
    end
  end

  def state(conn, _params) do
    if Auth.authorized?(conn) do
      json(conn, Content.full_state())
    else
      Auth.unauthorized(conn)
    end
  end

  def create_round(conn, params) do
    if Auth.authorized?(conn) do
      questions = params["questions"] || []
      replace_open = params["replace_open"] == true

      case Content.add_round(questions, replace_open) do
        {:ok, _round} ->
          json(conn, %{"ok" => true})

        {:error, :open_round_exists} ->
          conn |> put_status(409) |> json(%{"error" => "an open round exists"})
      end
    else
      Auth.unauthorized(conn)
    end
  end

  def update_design(conn, params) do
    if Auth.authorized?(conn) do
      {:ok, _} = Content.update_design(params["sections"] || [])
      json(conn, %{"ok" => true})
    else
      Auth.unauthorized(conn)
    end
  end

  def reset(conn, params) do
    if Auth.authorized?(conn) do
      case params["state"] do
        %{} = state ->
          case SeedLoader.load(state, force: params["force"] == true) do
            :ok ->
              Observe.emit("admin.reset", "succeeded", %{})
              json(conn, %{"ok" => true})

            {:error, {:would_drop_snapshot, round_ns}} ->
              conn
              |> put_status(409)
              |> json(%{"error" => "would_drop_snapshot", "rounds" => round_ns})
          end

        _ ->
          conn |> put_status(422) |> json(%{"error" => "state is required"})
      end
    else
      Auth.unauthorized(conn)
    end
  end
end
