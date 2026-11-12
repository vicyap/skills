defmodule DecisionSprite.Notifier.MailGateway do
  @moduledoc """
  Sends the submission notice as an email to Muse's Muse Mail inbox
  through the Sprites gateway Resend connection — the path proven by the
  2026-11-11 spike (~/workspace/decision-sprite-clean-pass/SPIKE.md):
  ~2–3 s from POST to a visible INBOUND/INTAKE record in Muse Mail,
  3/3 sends, Message-ID chain intact.

  Mechanics (spike-verified):
  - The sprite carries the label `conn:resend`; the gateway injects the
    Resend credentials — NO keys ever live in the sprite.
  - The connection's `gateway_base_url` is discovered from inside the
    sprite via GET https://api.sprites.dev/v1/gateway/list (the Resend
    Custom API connection: provider "custom_api", base_api_url
    https://api.resend.com). The resolved /emails URL is cached in app
    env; SUBMIT_MAIL_GATEWAY_URL overrides discovery entirely.
  - The mail carries ids and timestamps only — sprite, round,
    submitted_at, notice id — never answer content. Muse re-reads
    /admin/answers, the source of truth.

  Sender/recipient are config (`:mail_from`, `:mail_to`; env
  SUBMIT_MAIL_FROM / SUBMIT_MAIL_TO). The default recipient is Muse's
  Muse Mail address. The default sender is victor-muse@m.usetemi.com
  (Victor, 2026-11-11); the spike was proven from hello@m.usetemi.com.
  Both are on m.usetemi.com, a verified domain on the shared Resend
  account.
  """
  @behaviour DecisionSprite.Notifier

  alias DecisionSprite.Observe

  @gateway_list_url "https://api.sprites.dev/v1/gateway/list"
  @default_from "victor-muse@m.usetemi.com"
  @default_to "vicyap-muse@muse.ai"

  @impl true
  def deliver(payload) do
    case emails_url() do
      {:ok, url} -> post(url, payload)
      {:error, _} = err -> err
    end
  end

  defp post(url, payload) do
    from = Application.get_env(:decision_sprite, :mail_from) || @default_from
    to = Application.get_env(:decision_sprite, :mail_to) || @default_to

    body =
      Jason.encode!(%{
        "from" => from,
        "to" => [to],
        "subject" => "[decision sprite] #{payload["sprite"]} round #{payload["round"]} submitted",
        "text" =>
          Enum.join(
            [
              "A decision sprite round was submitted.",
              "",
              "sprite: #{payload["sprite"]}",
              "round: #{payload["round"]}",
              "submitted_at: #{payload["submitted_at"]}",
              "notice_id: #{payload["notice_id"]}",
              "",
              "Answers are NOT in this mail. Read them from the sprite's",
              "/admin/answers (Bearer admin token) — that is the source of truth.",
              "After reading, ack with POST /admin/ack {\"round\": #{payload["round"]}}."
            ],
            "\n"
          )
      })

    request =
      {String.to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json",
       body}

    case :httpc.request(:post, request, [timeout: 10_000], []) do
      {:ok, {{_, status, _}, _headers, _body}} when status in 200..299 ->
        Observe.emit("submission.notify", "succeeded", %{round: payload["round"]})
        :ok

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolve the gateway /emails URL: explicit config first, then the
  gateway list from inside the sprite (cached after first success).
  """
  def emails_url do
    case Application.get_env(:decision_sprite, :mail_gateway_url) do
      url when is_binary(url) and url != "" ->
        {:ok, url}

      _ ->
        discover()
    end
  end

  defp discover do
    request = {String.to_charlist(@gateway_list_url), []}

    with {:ok, {{_, 200, _}, _headers, body}} <-
           :httpc.request(:get, request, [timeout: 10_000], []),
         {:ok, %{"connections" => conns}} <- Jason.decode(to_string(body)),
         %{"gateway_base_url" => base} <-
           Enum.find(conns, fn c ->
             c["provider"] == "custom_api" and
               c["base_api_url"] == "https://api.resend.com"
           end) do
      url = String.trim_trailing(base, "/") <> "/emails"
      Application.put_env(:decision_sprite, :mail_gateway_url, url)
      {:ok, url}
    else
      _ -> {:error, :resend_gateway_connection_not_found}
    end
  end
end
