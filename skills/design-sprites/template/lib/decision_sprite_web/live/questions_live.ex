defmodule DecisionSpriteWeb.QuestionsLive do
  @moduledoc """
  The decisions sheet. Every change autosaves drafts server-side; there
  is exactly one action button, "Submit to Muse".

  Save semantics (clean pass, per the design review):
  - ordinary phx-change writes ONLY the targeted field, after the one
    cast in Content — identical-after-cast writes nothing;
  - phx-auto-recover is routed to "recover_draft": it never withdraws a
    submitted round and is staleness-checked against draft_revision;
    a stale recovery is not applied — it surfaces a banner with an
    explicit apply action;
  - a real edit to the latest submitted round withdraws it, but the
    frozen snapshot stays on record;
  - every error branch renders an explicit NOT-saved / Submit-FAILED
    status (never a stale "draft saved", never a crash);
  - the static (disconnected) render shows a connecting state with the
    Submit button disabled.
  """
  use DecisionSpriteWeb, :live_view

  alias DecisionSprite.{Content, Submissions}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Submissions.subscribe()
    {:ok, socket |> assign(:connected, connected?(socket)) |> load()}
  end

  defp load(socket) do
    case Content.latest_round() do
      nil ->
        socket
        |> assign(:current_tab, :questions)
        |> assign(:empty, true)
        |> assign(:round, nil)
        |> assign(:questions, [])
        |> assign(:anything_else, "")
        |> assign(:status_text, "")
        |> assign(:status_kind, :draft)
        |> assign(:recovery_conflict, false)
        |> assign(:recovered, nil)

      round ->
        questions = Content.questions_for(round.id)
        {text, kind} = base_status(socket.assigns.connected, round)

        socket
        |> assign(:current_tab, :questions)
        |> assign(:empty, false)
        |> assign(:round, round)
        |> assign(:questions, questions)
        |> assign(:anything_else, round.anything_else || "")
        |> assign(:status_text, text)
        |> assign(:status_kind, kind)
        |> assign(:recovery_conflict, false)
        |> assign(:recovered, nil)
    end
  end

  defp base_status(false, _round) do
    {"connecting… answers save automatically once this page is connected", :draft}
  end

  defp base_status(true, %_{status: "submitted"} = round) do
    date = String.slice(round.submitted_at || "", 0, 10)

    text =
      case Submissions.state_for(round.n) do
        %{status: "acked", acked_at: at} ->
          "Muse picked this up · #{clock_of(at)}"

        %{status: "sent"} ->
          "submitted · #{date} — sent to Muse's inbox, waiting for Muse to pick it up"

        %{status: "failed"} ->
          "submitted · #{date} — the message to Muse failed to send and is retrying; Muse has not been notified yet"

        _ ->
          "submitted · #{date} — sending the notice to Muse…"
      end

    {text, :submitted}
  end

  defp base_status(true, round) do
    if is_map(round.submitted_snapshot) do
      {"submission withdrawn — draft, answers autosave as you type", :draft}
    else
      {"draft — answers autosave as you type", :draft}
    end
  end

  # ---------------------------------------------------------------- events

  @impl true
  def handle_event("save", params, socket) do
    round = socket.assigns.round

    case Content.save_drafts(round.n, params["questions"] || %{}, anything_else(params, socket),
           target: parse_target(params)
         ) do
      {:ok, %{changed: true, withdrawn: withdrawn}} ->
        socket = load(socket)

        text =
          if withdrawn,
            do: "submission withdrawn — draft saved · #{clock()}",
            else: "draft saved · #{clock()}"

        {:noreply, socket |> assign(:status_text, text) |> assign(:status_kind, :draft)}

      {:ok, %{changed: false}} ->
        {:noreply, refresh_round(socket)}

      {:error, :sealed_round} ->
        {:noreply, error_status(socket, "NOT saved — this round is sealed")}

      {:error, _} ->
        {:noreply,
         error_status(
           socket,
           "NOT saved — something went wrong; what you typed is still in the form"
         )}
    end
  end

  def handle_event("recover_draft", params, socket) do
    round = socket.assigns.round

    opts = [
      recovery: true,
      revision: parse_revision(params),
      target: nil
    ]

    case Content.save_drafts(
           round.n,
           params["questions"] || %{},
           anything_else(params, socket),
           opts
         ) do
      {:ok, %{stale: true}} ->
        {:noreply,
         socket
         |> assign(:recovery_conflict, true)
         |> assign(:recovered, {params["questions"] || %{}, anything_else(params, socket)})}

      {:ok, %{changed: true}} ->
        socket = load(socket)

        {:noreply,
         socket
         |> assign(:status_text, "draft saved · #{clock()}")
         |> assign(:status_kind, :draft)}

      {:ok, %{changed: false}} ->
        {:noreply, refresh_round(socket)}

      {:error, _} ->
        {:noreply, error_status(socket, "NOT saved — recovered edits could not be applied")}
    end
  end

  def handle_event("apply_recovery", _params, socket) do
    case socket.assigns.recovered do
      nil ->
        {:noreply, socket}

      {answers, ae} ->
        round = socket.assigns.round

        case Content.save_drafts(round.n, answers, ae, target: nil) do
          {:ok, _} ->
            socket = load(socket)

            {:noreply,
             socket
             |> assign(:status_text, "draft saved · #{clock()}")
             |> assign(:status_kind, :draft)}

          {:error, _} ->
            {:noreply,
             error_status(socket, "NOT saved — the recovered edits could not be applied")}
        end
    end
  end

  def handle_event("submit", params, socket) do
    round = socket.assigns.round
    submission = {params["questions"] || %{}, anything_else(params, socket)}

    case Content.submit_round(round.n, submission) do
      {:ok, _} ->
        socket = load(socket)
        {text, kind} = base_status(true, socket.assigns.round)
        {:noreply, socket |> assign(:status_text, text) |> assign(:status_kind, kind)}

      {:error, :sealed_round} ->
        {:noreply, error_status(socket, "Submit FAILED — this round is sealed; nothing was sent")}

      {:error, _} ->
        {:noreply,
         error_status(
           socket,
           "Submit FAILED — not sent. Your answers are still in the form; try again."
         )}
    end
  end

  @impl true
  def handle_info({:submission_updated, n}, socket) do
    if socket.assigns.round && socket.assigns.round.n == n do
      round = Content.latest_round()
      {text, kind} = base_status(true, round)

      {:noreply,
       socket |> assign(:round, round) |> assign(:status_text, text) |> assign(:status_kind, kind)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------- helpers

  defp refresh_round(socket) do
    round = Content.latest_round()

    if round do
      socket
      |> assign(:round, round)
      |> assign(:questions, Content.questions_for(round.id))
    else
      socket
    end
  end

  defp error_status(socket, text) do
    socket |> assign(:status_text, text) |> assign(:status_kind, :error)
  end

  defp anything_else(params, socket) do
    case Map.fetch(params, "anything_else") do
      {:ok, v} -> v
      :error -> socket.assigns.anything_else
    end
  end

  defp parse_target(params) do
    case params["_target"] do
      ["questions", qid, field] ->
        case %{"choice" => :choice, "other_text" => :other_text, "comment" => :comment}[field] do
          nil -> nil
          f -> {:field, qid, f}
        end

      ["anything_else"] ->
        :anything_else

      _ ->
        nil
    end
  end

  defp parse_revision(params) do
    case Integer.parse(params["revision"] || "") do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp clock do
    Time.utc_now() |> Calendar.strftime("%H:%M:%S")
  end

  defp clock_of(iso) when is_binary(iso), do: String.slice(iso, 11, 8)
  defp clock_of(_), do: ""

  defp show_other?(q) do
    q.choice == "other" or (is_binary(q.other_text) and q.other_text != "")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @empty do %>
      <section class="card">
        <p class="eyebrow">Decisions</p>
        <h2 class="headline">No open decisions right now</h2>
        <p>
          Your answers are saved and with Muse. The next round of questions,
          if one is needed, will appear here. See the design tab for your
          answers so far.
        </p>
      </section>
    <% else %>
      <p class="mono meta">
        Round {@round.n} · {length(@questions)} decisions · pick one option per
        question, or use Other, and add a comment whenever the options do not
        quite say it.
      </p>
      <%= if @round.status == "submitted" do %>
        <p class="notice">
          This round is submitted. Editing an answer for real withdraws the
          submission until you submit again — the copy Muse received stays
          on record either way.
        </p>
      <% end %>
      <%= if @recovery_conflict do %>
        <div class="recovery-banner" role="alert">
          <p>
            Unsaved edits from before the connection dropped were NOT applied —
            this page already has newer state.
          </p>
          <button type="button" phx-click="apply_recovery">Apply those edits instead</button>
        </div>
      <% end %>
      <form
        id="answers-form"
        phx-change="save"
        phx-submit="submit"
        phx-auto-recover="recover_draft"
        phx-hook="DraftFlush"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="revision" value={@round.draft_revision} />
        <section :for={q <- @questions} class="card q" id={"q-#{q.qid}"}>
          <p class="prompt">{q.prompt}</p>
          <p :if={q.context not in [nil, ""]} class="ctx">{q.context}</p>

          <% opts = Content.render_options(q) %>
          <%= if opts == [] do %>
            <label class="clab" for={"q-#{q.qid}-other"}>Your answer</label>
            <input
              class="otherbox show"
              type="text"
              id={"q-#{q.qid}-other"}
              name={"questions[#{q.qid}][other_text]"}
              value={q.other_text || ""}
              placeholder="Say it your way"
              phx-debounce="400"
            />
          <% else %>
            <div class="opts" role="radiogroup">
              <label
                :for={o <- opts}
                class={["opt", q.choice == o["value"] && "sel"]}
              >
                <input
                  type="radio"
                  name={"questions[#{q.qid}][choice]"}
                  value={o["value"]}
                  checked={q.choice == o["value"]}
                  phx-debounce="0"
                />
                <span class="opt-body">
                  <span class="opt-label">{o["label"]}</span>
                  <span :if={o["detail"] not in [nil, ""]} class="opt-detail">{o["detail"]}</span>
                </span>
              </label>
            </div>
            <input
              class={["otherbox", show_other?(q) && "show"]}
              type="text"
              id={"q-#{q.qid}-other"}
              name={"questions[#{q.qid}][other_text]"}
              value={q.other_text || ""}
              placeholder="Other: say it your way"
              aria-label="Other (specify)"
              phx-debounce="400"
            />
          <% end %>

          <label class="clab" for={"q-#{q.qid}-comment"}>
            Comment (optional, saved word for word)
          </label>
          <textarea
            class="comment"
            id={"q-#{q.qid}-comment"}
            name={"questions[#{q.qid}][comment]"}
            placeholder="Qualifications, exceptions, numbers..."
            phx-debounce="400"
          >{q.comment || ""}</textarea>
        </section>

        <section class="card q">
          <p class="prompt">Anything else?</p>
          <label class="clab" for="anything-else">Free text, saved word for word</label>
          <textarea
            class="comment"
            id="anything-else"
            name="anything_else"
            placeholder="Anything the questions missed..."
            phx-debounce="400"
          >{@anything_else}</textarea>
        </section>

        <div class="submitbar">
          <p
            class={[
              "mono",
              "status",
              @status_kind == :submitted && "is-submitted",
              @status_kind == :error && "is-error"
            ]}
            id="save-status"
          >
            {@status_text}
          </p>
          <button class="go" type="submit" disabled={not @connected}>Submit to Muse</button>
        </div>
      </form>
    <% end %>
    """
  end
end
