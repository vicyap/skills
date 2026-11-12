defmodule DecisionSprite.Content do
  @moduledoc """
  The domain context: design doc, rounds, questions, drafts, snapshots.

  Semantics (clean pass, 2026-11-11, per the Opus 5.5 design review):

  - Drafts live on Question and autosave. Every incoming value passes
    through ONE cast (`cast_text/1` — newline-normalize, trim, ""→nil),
    the same values that are written, so an autosave whose values are
    identical after casting writes nothing and withdraws nothing
    (idempotent saves; LiveView form recovery can never destroy data).
  - Ordinary change events write only the targeted field; recovery
    events (phx-auto-recover) are staleness-checked against the round's
    `draft_revision` and NEVER withdraw a submitted round.
  - Submit freezes a verbatim snapshot onto the Round in ONE transaction
    together with its outbox notice (R2). The snapshot embeds the
    question text, so a round stays readable exactly as submitted even
    if questions are later reseeded.
  - Freeze means freeze: a snapshot is never cleared. A real edit to the
    latest submitted round withdraws it (status open, `withdrawn_at`
    stamped, snapshot kept). Non-latest rounds are sealed: saves and
    submits against them are refused in this module, not just the UI.
  - No bang calls on the save/submit paths: errors come back as
    {:error, reason} so the LiveView can show an explicit NOT-saved /
    Submit-FAILED state instead of crashing or lying.
  """

  alias DecisionSprite.Domain
  alias DecisionSprite.Observe
  alias DecisionSprite.Repo
  alias DecisionSprite.Resources.{DesignDoc, Question, Round, SubmissionNotice}

  @default_title "Decisions with Muse"

  # ---------------------------------------------------------------- title

  def app_title do
    System.get_env("APP_TITLE") || design_title() || @default_title
  end

  defp design_title do
    case design() do
      %DesignDoc{title: t} when is_binary(t) and t != "" -> t
      _ -> nil
    end
  end

  def template_version do
    :decision_sprite |> Application.spec(:vsn) |> to_string()
  end

  # ---------------------------------------------------------------- reads

  def design do
    DesignDoc
    |> Ash.read!(domain: Domain)
    |> Enum.sort_by(& &1.id)
    |> List.first()
  end

  def design_version, do: design() |> Kernel.||(%DesignDoc{version: 0}) |> Map.get(:version)

  def rounds do
    Round
    |> Ash.read!(domain: Domain)
    |> Enum.sort_by(& &1.n)
  end

  def rounds_count, do: Ash.count!(Round, domain: Domain)

  def questions_for(round_id) do
    Question
    |> Ash.read!(domain: Domain)
    |> Enum.filter(&(&1.round_id == round_id))
    |> Enum.sort_by(& &1.position)
  end

  def latest_round do
    rounds() |> List.last()
  end

  def round_with_questions(%Round{} = round) do
    %{round: round, questions: questions_for(round.id)}
  end

  defp find_round(round_n), do: Enum.find(rounds(), &(&1.n == round_n))

  defp latest?(round), do: match?(%Round{}, latest_round()) and latest_round().id == round.id

  # ---------------------------------------------------------- the one cast

  @doc """
  The single normalization every draft value passes through before it is
  compared or written (the write path's cast): CRLF/CR → LF, surrounding
  whitespace trimmed, empty → nil. Comparing cast(incoming) against
  stored values is what makes autosave idempotent after write-path
  normalization.
  """
  def cast_text(nil), do: nil

  def cast_text(v) when is_binary(v) do
    v =
      v
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.trim()

    if v == "", do: nil, else: v
  end

  def cast_text(v), do: v |> to_string() |> cast_text()

  # ------------------------------------------------------- answer shaping

  @doc """
  The effective answer object for a question: the snapshot entry for a
  submitted round, the draft for an open round. Returns nil when the
  draft is fully empty (open rounds); snapshot entries are returned as
  stored for submitted rounds.
  """
  def effective_answer(%Round{status: "submitted", submitted_snapshot: snap}, %Question{} = q)
      when is_map(snap) do
    case snapshot_entry(snap, q.qid) do
      %{} = entry -> normalize_answer(entry)
      _ -> %{"choice" => "", "choice_label" => "", "other_text" => "", "comment" => ""}
    end
  end

  def effective_answer(%Round{}, %Question{} = q) do
    draft_answer(q)
  end

  @doc """
  The answer frozen in a round's snapshot for one question, or nil.
  Handles both snapshot formats: the current one
  (%{qid => %{"prompt" => _, "answer" => answer}}) and the legacy one
  (%{qid => answer}) written before the clean pass.
  """
  def snapshot_entry(snap, qid) when is_map(snap) do
    case get_in(snap, ["questions", qid]) do
      %{"answer" => a} when is_map(a) -> a
      %{} = a -> a
      _ -> nil
    end
  end

  def snapshot_entry(_, _), do: nil

  @doc "Draft as an answer object, or nil when choice/other_text/comment are all empty."
  def draft_answer(%Question{} = q) do
    if blank?(q.choice) and blank?(q.other_text) and blank?(q.comment) do
      nil
    else
      %{
        "choice" => q.choice || "",
        "choice_label" => q.choice_label || "",
        "other_text" => q.other_text || "",
        "comment" => q.comment || ""
      }
    end
  end

  def normalize_answer(a) when is_map(a) do
    %{
      "choice" => str(a["choice"] || a[:choice]),
      "choice_label" => str(a["choice_label"] || a[:choice_label]),
      "other_text" => str(a["other_text"] || a[:other_text]),
      "comment" => str(a["comment"] || a[:comment])
    }
  end

  def answered?(nil), do: false

  def answered?(a) when is_map(a) do
    not (blank?(a["choice"]) and blank?(a["other_text"]) and blank?(a["comment"]))
  end

  @doc "The frozen snapshot shaped for output (list of questions, prompt included)."
  def snapshot_view(%Round{submitted_snapshot: snap} = r, questions) when is_map(snap) do
    %{
      "submitted_at" => snap["submitted_at"] || r.submitted_at,
      "anything_else" => snap["anything_else"] || "",
      "questions" =>
        for q <- questions do
          entry = get_in(snap, ["questions", q.qid]) || %{}

          %{
            "id" => q.qid,
            "prompt" => entry["prompt"] || q.prompt,
            "answer" => normalize_answer(entry["answer"] || entry)
          }
        end
    }
  end

  def snapshot_view(%Round{}, _questions), do: nil

  # ---------------------------------------------------------------- views

  @doc "The /admin/answers shape — byte-compatible with the Python sprites."
  def answers_view do
    rounds_out =
      for r <- rounds() do
        qs = questions_for(r.id)

        base = %{
          "n" => r.n,
          "status" => r.status,
          "submitted_at" => if(r.status == "submitted", do: r.submitted_at, else: nil),
          "anything_else" => snapshot_or_draft_anything_else(r),
          "questions" =>
            for q <- qs do
              ans = effective_answer(r, q)

              %{
                "id" => q.qid,
                "prompt" => q.prompt,
                "answered" => answered?(ans),
                "answer" => ans
              }
            end
        }

        # A withdrawn round (open again, but a snapshot survives) also
        # reports its frozen snapshot, so the submission is never lost
        # from view. Never-submitted and currently-submitted rounds keep
        # the original shape exactly.
        if r.status == "open" and is_map(r.submitted_snapshot) do
          base
          |> Map.put("withdrawn_since", r.withdrawn_at)
          |> Map.put("last_snapshot", snapshot_view(r, qs))
        else
          base
        end
      end

    %{"ok" => true, "design_version" => design_version(), "rounds" => rounds_out}
  end

  defp snapshot_or_draft_anything_else(%Round{status: "submitted", submitted_snapshot: snap})
       when is_map(snap) do
    Map.get(snap, "anything_else")
  end

  defp snapshot_or_draft_anything_else(%Round{} = r), do: r.anything_else

  @doc "The /api/state shape — the full Python state document."
  def full_state do
    d = design()

    design_map =
      case d do
        nil ->
          %{"version" => 0, "updated_at" => "", "sections" => []}

        %DesignDoc{} ->
          base = %{
            "version" => d.version,
            "updated_at" => d.updated_at,
            "sections" => normalize_sections(d.sections)
          }

          if d.title, do: Map.put(base, "title", d.title), else: base
      end

    rounds_out =
      for r <- rounds() do
        qs = questions_for(r.id)

        base = %{
          "n" => r.n,
          "status" => r.status,
          "submitted_at" => r.submitted_at,
          "anything_else" => r.anything_else,
          "questions" =>
            for q <- qs do
              %{
                "id" => q.qid,
                "prompt" => q.prompt,
                "context" => q.context,
                "options" => normalize_options(q.options),
                "answer" => effective_answer(r, q)
              }
            end
        }

        if r.status == "open" and is_map(r.submitted_snapshot) do
          base
          |> Map.put("withdrawn_since", r.withdrawn_at)
          |> Map.put("last_snapshot", snapshot_view(r, qs))
        else
          base
        end
      end

    %{"design" => design_map, "rounds" => rounds_out}
  end

  def normalize_sections(sections) when is_list(sections) do
    for s <- sections do
      %{
        "heading" => str(s["heading"] || s[:heading]),
        "status" => s["status"] || s[:status],
        "body" => str(s["body"] || s[:body])
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end
  end

  def normalize_sections(_), do: []

  def normalize_options(options) when is_list(options) do
    for o <- options do
      %{
        "value" => str(o["value"] || o[:value]),
        "label" => str(o["label"] || o[:label]),
        "detail" => str(o["detail"] || o[:detail])
      }
    end
  end

  def normalize_options(_), do: []

  @doc """
  Options for rendering: the seed's options, with an "Other (specify)"
  radio guaranteed inside the group when the question has named options
  but no Other of its own. Zero named options render as free-text.
  """
  def render_options(%Question{} = q) do
    opts = normalize_options(q.options)
    named = Enum.reject(opts, &(&1["value"] == "other"))

    cond do
      named == [] ->
        []

      Enum.any?(opts, &(&1["value"] == "other")) ->
        opts

      true ->
        opts ++
          [
            %{
              "value" => "other",
              "label" => "Other (specify)",
              "detail" => "Say it your way in the box below."
            }
          ]
    end
  end

  def choice_label(%Question{} = q, choice) do
    q.options
    |> normalize_options()
    |> Kernel.++(render_options(q))
    |> Enum.find(%{}, &(&1["value"] == choice))
    |> Map.get("label", "")
  end

  defp label_for(_q, choice) when choice in [nil, ""], do: ""

  defp label_for(q, choice) do
    opts = render_options(q)

    case Enum.find(opts, &(&1["value"] == choice)) do
      nil -> ""
      o -> o["label"]
    end
  end

  # ---------------------------------------------------------------- writes

  @doc """
  Autosave drafts for a round. `answers` maps qid => partial attrs
  (choice / other_text / comment; choice_label is derived). LiveView
  meta keys are stripped by only ever reading those three fields.

  Options:
  - `target:` nil (compare every field — submit, beacon, tests),
    `{:field, qid, field}` (an ordinary phx-change: write ONLY that
    field), or `:anything_else`.
  - `recovery: true` for phx-auto-recover events: never withdraws, and
    when `revision:` is given and differs from the round's current
    draft_revision the event is stale and writes nothing.

  Returns {:ok, %{round:, questions:, withdrawn:, changed:, stale:}} or
  {:error, :no_such_round | :sealed_round | term()}.
  """
  def save_drafts(round_n, answers, anything_else \\ :unchanged, opts \\ []) do
    case find_round(round_n) do
      nil ->
        {:error, :no_such_round}

      %Round{} = round ->
        cond do
          not latest?(round) ->
            {:error, :sealed_round}

          # Recovery writes ONLY into a still-open round whose revision
          # matches. A submitted round or a stale revision: write
          # nothing and report the conflict so the UI can offer the
          # recovered edits behind an explicit apply action.
          Keyword.get(opts, :recovery, false) and
              (round.status == "submitted" or
                 stale_revision?(round, Keyword.get(opts, :revision))) ->
            {:ok,
             %{
               round: round,
               questions: questions_for(round.id),
               withdrawn: false,
               changed: false,
               stale: true
             }}

          true ->
            do_save(round, answers, anything_else, opts)
        end
    end
  end

  defp stale_revision?(_round, nil), do: false
  defp stale_revision?(round, revision), do: revision != round.draft_revision

  defp do_save(round, answers, anything_else, opts) do
    questions = questions_for(round.id)
    recovery? = Keyword.get(opts, :recovery, false)
    target = Keyword.get(opts, :target)

    q_writes = planned_question_writes(questions, answers, target)
    ae_write = planned_anything_else_write(round, anything_else, target)

    if q_writes == [] and ae_write == :unchanged do
      {:ok, %{round: round, questions: questions, withdrawn: false, changed: false, stale: false}}
    else
      case transact(fn -> apply_save(round, q_writes, ae_write, recovery?) end) do
        {:ok, %{round: updated, withdrawn: withdrawn}} ->
          if withdrawn do
            Observe.emit("answers.withdrawn", "succeeded", %{round: round.n})
          end

          Observe.emit("answers.autosaved", "succeeded", %{
            round: round.n,
            questions: length(questions)
          })

          {:ok,
           %{
             round: updated,
             questions: questions_for(round.id),
             withdrawn: withdrawn,
             changed: true,
             stale: false
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  # Which question fields actually change, after the one cast. In
  # targeted mode only the targeted field is even considered, so a stale
  # tab's whole-form echo cannot clobber newer answers in other fields.
  defp planned_question_writes(questions, answers, target) do
    answers = if is_map(answers), do: answers, else: %{}

    for q <- questions,
        attrs = Map.get(answers, q.qid),
        is_map(attrs),
        fields = changed_fields(q, attrs, target),
        fields != %{} do
      {q, fields}
    end
  end

  defp changed_fields(q, attrs, target) do
    candidates =
      case target do
        {:field, qid, field} when qid == q.qid ->
          [{field, Map.get(attrs, Atom.to_string(field))}]

        {:field, _, _} ->
          []

        _ ->
          [
            {:choice, Map.get(attrs, "choice")},
            {:other_text, Map.get(attrs, "other_text")},
            {:comment, Map.get(attrs, "comment")}
          ]
      end

    # NOTE: this must not be a comprehension with `casted = cast_text(raw)`
    # as a filter step — a match whose value is nil (a cleared field) is
    # falsy, so the comprehension silently drops every clear and the old
    # value is resurrected on the next render. Reduce explicitly instead.
    Enum.reduce(candidates, %{}, fn {field, raw}, acc ->
      if raw == nil do
        acc
      else
        casted = cast_text(raw)

        if casted == cast_text(Map.get(q, field)) do
          acc
        else
          Map.put(acc, field, casted)
        end
      end
    end)
  end

  defp planned_anything_else_write(round, anything_else, target) do
    cond do
      anything_else == :unchanged -> :unchanged
      target not in [nil, :anything_else] -> :unchanged
      cast_text(anything_else) == cast_text(round.anything_else) -> :unchanged
      true -> cast_text(anything_else)
    end
  end

  defp apply_save(round, q_writes, ae_write, recovery?) do
    withdrawn? = not recovery? and round.status == "submitted"

    with {:ok, round} <-
           if(withdrawn?,
             do:
               update_record(round, %{
                 status: "open",
                 withdrawn_at: now_iso(),
                 draft_revision: round.draft_revision + 1
               }),
             else: {:ok, round}
           ),
         {:ok, _} <- apply_question_writes(q_writes),
         {:ok, round} <-
           if(ae_write != :unchanged,
             do: update_record(round, %{anything_else: ae_write}),
             else: {:ok, round}
           ),
         {:ok, round} <-
           if(withdrawn?,
             do: {:ok, round},
             else: update_record(round, %{draft_revision: round.draft_revision + 1})
           ) do
      {:ok, %{round: round, withdrawn: withdrawn?}}
    end
  end

  defp apply_question_writes(q_writes) do
    Enum.reduce_while(q_writes, {:ok, []}, fn {q, fields}, {:ok, acc} ->
      attrs =
        fields
        |> Map.put_new(:choice_label, q.choice_label)
        |> then(fn a ->
          if Map.has_key?(fields, :choice),
            do: Map.put(a, :choice_label, label_for(q, fields.choice) || ""),
            else: a
        end)

      case q
           |> Ash.Changeset.for_update(:save_draft, attrs, domain: Domain)
           |> Ash.update() do
        {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc """
  Freeze the round: optionally apply the submit event's own form values
  first (same normalized, per-field save), then snapshot + outbox notice
  in ONE transaction. Resubmitting an unchanged submitted round is a
  no-op ({:ok, %{already: true}}). Returns {:ok, %{round:, notice:}}.
  """
  def submit_round(round_n, submission \\ nil)

  def submit_round(round_n, submission) do
    case find_round(round_n) do
      nil ->
        {:error, :no_such_round}

      %Round{} = round ->
        if latest?(round) do
          do_submit(round, submission)
        else
          {:error, :sealed_round}
        end
    end
  end

  defp do_submit(round, submission) do
    {answers, anything_else} =
      case submission do
        nil -> {%{}, :unchanged}
        {a, ae} -> {a, ae}
      end

    questions = questions_for(round.id)
    q_writes = planned_question_writes(questions, answers, nil)
    ae_write = planned_anything_else_write(round, anything_else, nil)

    already? =
      round.status == "submitted" and is_map(round.submitted_snapshot) and
        q_writes == [] and ae_write == :unchanged

    if already? do
      {:ok,
       %{round: round, notice: DecisionSprite.Submissions.latest_for(round.n), already: true}}
    else
      result =
        transact(fn ->
          with {:ok, _} <- apply_question_writes(q_writes),
               {:ok, round} <-
                 if(ae_write != :unchanged,
                   do: update_record(round, %{anything_else: ae_write}),
                   else: {:ok, round}
                 ) do
            ts = now_iso()
            fresh = Ash.get!(Round, round.id, domain: Domain)
            snapshot = build_snapshot(fresh, questions_for(round.id), ts)

            with {:ok, submitted} <-
                   update_record(fresh, %{
                     status: "submitted",
                     submitted_at: ts,
                     submitted_snapshot: snapshot,
                     withdrawn_at: nil,
                     draft_revision: fresh.draft_revision + 1
                   }),
                 {:ok, notice} <- create_notice(round.n, ts) do
              {:ok, %{round: submitted, notice: notice, already: false}}
            end
          end
        end)

      case result do
        {:ok, %{notice: notice} = out} ->
          answered =
            Enum.count(
              questions_for(round.id),
              fn q -> draft_answer(q) != nil end
            )

          Observe.emit("answers.submitted", "succeeded", %{round: round.n, answered: answered})
          if notice, do: DecisionSprite.Submissions.kick()
          {:ok, out}

        {:error, _} = err ->
          err
      end
    end
  end

  defp build_snapshot(round, questions, ts) do
    %{
      "submitted_at" => ts,
      "anything_else" => round.anything_else || "",
      "questions" =>
        Map.new(questions, fn q ->
          {q.qid,
           %{
             "prompt" => q.prompt,
             "context" => q.context,
             "answer" => %{
               "choice" => q.choice || "",
               "choice_label" => q.choice_label || label_for(q, q.choice),
               "other_text" => q.other_text || "",
               "comment" => q.comment || ""
             }
           }}
        end)
    }
  end

  defp create_notice(round_n, ts) do
    SubmissionNotice
    |> Ash.Changeset.for_create(
      :create,
      %{
        round_n: round_n,
        submitted_at: ts,
        status: "pending",
        attempts: 0,
        created_at: ts,
        updated_at: ts
      },
      domain: Domain
    )
    |> Ash.create()
  end

  @doc """
  Append a new open round (POST /api/rounds semantics). With
  replace_open, only open rounds WITHOUT a snapshot are replaced — a
  round that has ever submitted is never destroyed here.
  """
  def add_round(question_maps, replace_open) do
    if replace_open do
      for r <- rounds(), r.status == "open" and not is_map(r.submitted_snapshot) do
        for q <- questions_for(r.id), do: Ash.destroy!(q, domain: Domain)
        Ash.destroy!(r, domain: Domain)
      end
    end

    if Enum.any?(rounds(), &(&1.status == "open")) do
      {:error, :open_round_exists}
    else
      n = (rounds() |> Enum.map(& &1.n) |> Enum.max(fn -> 0 end)) + 1

      round =
        Round
        |> Ash.Changeset.for_create(
          :create,
          %{n: n, status: "open", submitted_at: nil, anything_else: nil},
          domain: Domain
        )
        |> Ash.create!()

      create_questions(round, question_maps)
      Observe.emit("admin.rounds_updated", "succeeded", %{round: n})
      {:ok, round}
    end
  end

  def create_questions(%Round{} = round, question_maps) do
    question_maps
    |> Enum.with_index()
    |> Enum.each(fn {qm, idx} ->
      answer = qm["answer"] || qm[:answer]

      draft =
        if is_map(answer) do
          %{
            choice: empty_to_nil(answer["choice"]),
            choice_label: empty_to_nil(answer["choice_label"]),
            other_text: empty_to_nil(answer["other_text"]),
            comment: empty_to_nil(answer["comment"])
          }
        else
          %{}
        end

      Question
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{
            round_id: round.id,
            qid: str(qm["id"] || qm[:id] || qm["qid"]),
            prompt: str(qm["prompt"]),
            context: qm["context"],
            options: normalize_options(qm["options"] || []),
            position: idx
          },
          draft
        ),
        domain: Domain
      )
      |> Ash.create!()
    end)

    :ok
  end

  @doc "Replace the design sections (POST /api/design semantics): bumps version."
  def update_design(sections) do
    now = now_iso()

    updated =
      case design() do
        nil ->
          DesignDoc
          |> Ash.Changeset.for_create(
            :create,
            %{version: 1, updated_at: now, sections: normalize_sections(sections)},
            domain: Domain
          )
          |> Ash.create!()

        %DesignDoc{} = d ->
          d
          |> Ash.Changeset.for_update(
            :update,
            %{
              version: d.version + 1,
              updated_at: now,
              sections: normalize_sections(sections)
            },
            domain: Domain
          )
          |> Ash.update!()
      end

    Observe.emit("admin.design_updated", "succeeded", %{version: updated.version})
    {:ok, updated}
  end

  @doc "Round numbers that currently hold a submitted snapshot."
  def snapshot_rounds do
    rounds() |> Enum.filter(&is_map(&1.submitted_snapshot)) |> Enum.map(& &1.n)
  end

  @doc "Delete all content (used by the seed loader inside its transaction, and tests)."
  def wipe! do
    for n <- Ash.read!(SubmissionNotice, domain: Domain), do: Ash.destroy!(n, domain: Domain)
    for q <- Ash.read!(Question, domain: Domain), do: Ash.destroy!(q, domain: Domain)
    for r <- Ash.read!(Round, domain: Domain), do: Ash.destroy!(r, domain: Domain)
    for d <- Ash.read!(DesignDoc, domain: Domain), do: Ash.destroy!(d, domain: Domain)
    :ok
  end

  # ---------------------------------------------------------------- helpers

  defp update_record(record, attrs) do
    record
    |> Ash.Changeset.for_update(:update, attrs, domain: Domain)
    |> Ash.update()
  end

  defp transact(fun) do
    case Repo.transaction(fn ->
           case fun.() do
             {:ok, v} -> v
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, reason}
    end
  end

  def now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace_suffix("Z", "+00:00")
  end

  def blank?(v), do: v == nil or (is_binary(v) and String.trim(v) == "")

  defp str(nil), do: ""
  defp str(v) when is_binary(v), do: v
  defp str(v), do: to_string(v)

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(v), do: v
end
