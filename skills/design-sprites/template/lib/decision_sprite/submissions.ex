defmodule DecisionSprite.Submissions do
  @moduledoc """
  The submission outbox (R2). Notices are created by Content inside the
  submit transaction; this worker delivers them through the Notifier
  adapter with backoff, and records Muse's explicit ack.

  Delivery semantics: a notice is "sent" when the adapter confirms the
  send; it becomes "acked" ONLY through `ack/1`, called by Muse (via the
  Bearer-gated POST /admin/ack) after it has read the round. Nothing here
  infers receipt from a fetch.
  """

  use GenServer

  alias DecisionSprite.{Notifier, Observe}
  alias DecisionSprite.Domain
  alias DecisionSprite.Resources.SubmissionNotice

  @max_attempts 5
  @topic "submissions"

  # ------------------------------------------------------------------ API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "Ask the worker to (re)drive pending notices (post-submit, post-boot)."
  def kick do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :drive)
    :ok
  end

  @doc "Drive pending notices synchronously (tests / ops). Returns :ok."
  def drive_now do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :drive_now, 30_000)
    else
      :ok
    end
  end

  @doc "The latest notice for a round, or nil."
  def latest_for(round_n) do
    SubmissionNotice
    |> Ash.read!(domain: Domain)
    |> Enum.filter(&(&1.round_n == round_n))
    |> Enum.sort_by(& &1.id)
    |> List.last()
  end

  @doc "Page-facing submission state for a round."
  def state_for(round_n) do
    case latest_for(round_n) do
      nil ->
        nil

      n ->
        %{
          status: n.status,
          submitted_at: n.submitted_at,
          acked_at: n.acked_at,
          sent_at: n.sent_at
        }
    end
  end

  @doc """
  Record Muse's ack for a round's latest sent notice. Only a notice in
  "sent" state can be acked. Broadcasts so an open page updates live.
  """
  def ack(round_n) do
    case latest_for(round_n) do
      %SubmissionNotice{status: "sent"} = notice ->
        notice
        |> Ash.Changeset.for_update(
          :update,
          %{
            status: "acked",
            acked_at: DecisionSprite.Content.now_iso(),
            updated_at: DecisionSprite.Content.now_iso()
          },
          domain: Domain
        )
        |> Ash.update()
        |> case do
          {:ok, updated} ->
            Observe.emit("submission.acked", "succeeded", %{round: round_n})
            broadcast(round_n)
            {:ok, updated}

          {:error, _} = err ->
            err
        end

      %SubmissionNotice{} ->
        {:error, :not_sent}

      nil ->
        {:error, :no_notice}
    end
  end

  def subscribe, do: Phoenix.PubSub.subscribe(DecisionSprite.PubSub, @topic)

  def broadcast(round_n),
    do: Phoenix.PubSub.broadcast(DecisionSprite.PubSub, @topic, {:submission_updated, round_n})

  # ------------------------------------------------------------- GenServer

  @impl true
  def init(_opts) do
    # Re-drive anything left pending by a crash/restart, shortly after boot.
    Process.send_after(self(), :drive, 5_000)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:drive_now, _from, state) do
    drive()
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:drive, state) do
    drive()
    {:noreply, state}
  end

  @impl true
  def handle_info(:drive, state) do
    drive()
    {:noreply, state}
  end

  def handle_info({:retry, notice_id}, state) do
    case Ash.get(SubmissionNotice, notice_id, domain: Domain) do
      {:ok, %SubmissionNotice{status: status} = notice} when status in ["pending", "failed"] ->
        attempt(notice)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp drive do
    SubmissionNotice
    |> Ash.read!(domain: Domain)
    |> Enum.filter(&(&1.status in ["pending", "failed"]))
    |> Enum.each(&attempt/1)
  end

  defp attempt(notice) do
    if notice.attempts >= @max_attempts do
      mark(notice, %{status: "failed", last_error: "max_attempts_exceeded"})

      Observe.emit("submission.notify", "failed", %{round: notice.round_n, reason: "max_attempts"})
    else
      payload = Notifier.payload(notice)

      case Notifier.deliver(payload) do
        :ok ->
          mark(notice, %{
            status: "sent",
            attempts: notice.attempts + 1,
            sent_at: DecisionSprite.Content.now_iso(),
            last_error: nil
          })

          broadcast(notice.round_n)

        {:error, reason} ->
          attempts = notice.attempts + 1

          mark(notice, %{
            status: "failed",
            attempts: attempts,
            last_error: inspect(reason) |> String.slice(0, 200)
          })

          Observe.emit("submission.notify", "failed", %{
            round: notice.round_n,
            reason: "delivery_failed"
          })

          if attempts < @max_attempts do
            Process.send_after(self(), {:retry, notice.id}, backoff_ms(attempts))
          end

          broadcast(notice.round_n)
      end
    end
  end

  defp backoff_ms(attempts), do: min(30_000 * attempts, 120_000)

  defp mark(notice, attrs) do
    attrs = Map.put(attrs, :updated_at, DecisionSprite.Content.now_iso())

    notice
    |> Ash.Changeset.for_update(:update, attrs, domain: Domain)
    |> Ash.update()
  end
end
