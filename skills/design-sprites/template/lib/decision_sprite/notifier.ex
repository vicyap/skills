defmodule DecisionSprite.Notifier do
  @moduledoc """
  The one adapter boundary for submission notices (R2). A notice is a
  small map of ids and timestamps — `%{sprite, round, submitted_at,
  notice_id}` — NEVER answer content; Muse re-reads the answers from
  /admin/answers, the source of truth, when the notice arrives.

  The implementation is chosen by config `:decision_sprite, :notifier`
  (env `SUBMIT_NOTIFIER` in prod: "webhook" | "mail_gateway" | "log").
  """

  @callback deliver(notice :: map()) :: :ok | {:error, term()}

  def impl do
    Application.get_env(:decision_sprite, :notifier, DecisionSprite.Notifier.Log)
  end

  def deliver(notice), do: impl().deliver(notice)

  @doc "The notice payload for a SubmissionNotice row (ids/timestamps only)."
  def payload(notice) do
    %{
      "sprite" => Application.get_env(:decision_sprite, :sprite_name) || "decision-sprite",
      "round" => notice.round_n,
      "submitted_at" => notice.submitted_at,
      "notice_id" => notice.id
    }
  end
end

defmodule DecisionSprite.Notifier.Log do
  @moduledoc """
  Default adapter: records the attempt through Observe and reports
  `{:error, :no_delivery_configured}`. This is deliberate — with no real
  channel configured the submission stays visibly UNDELIVERED (the page
  keeps saying so) instead of silently pretending Muse was notified.
  """
  @behaviour DecisionSprite.Notifier

  alias DecisionSprite.Observe

  @impl true
  def deliver(payload) do
    Observe.emit("submission.notify", "skipped", %{
      round: payload["round"],
      reason: "no_delivery_configured"
    })

    {:error, :no_delivery_configured}
  end
end

defmodule DecisionSprite.Notifier.Webhook do
  @moduledoc """
  POSTs the notice JSON to `SUBMIT_NOTIFY_URL` (Bearer
  `SUBMIT_NOTIFY_TOKEN` when set) with :httpc — no extra deps.
  """
  @behaviour DecisionSprite.Notifier

  alias DecisionSprite.Observe

  @impl true
  def deliver(notice) do
    url = Application.get_env(:decision_sprite, :notify_url)
    token = Application.get_env(:decision_sprite, :notify_token)

    cond do
      not is_binary(url) or url == "" ->
        {:error, :notify_url_not_configured}

      true ->
        headers =
          [{~c"content-type", ~c"application/json"}] ++
            if token, do: [{~c"authorization", String.to_charlist("Bearer " <> token)}], else: []

        request = {String.to_charlist(url), headers, ~c"application/json", Jason.encode!(notice)}

        case :httpc.request(:post, request, [timeout: 10_000], []) do
          {:ok, {{_, status, _}, _headers, _body}} when status in 200..299 ->
            Observe.emit("submission.notify", "succeeded", %{round: notice["round"]})
            :ok

          {:ok, {{_, status, _}, _headers, _body}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
