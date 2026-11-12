defmodule DecisionSprite.SeedLoader do
  @moduledoc """
  Loads a full state document (the Python `state.json` shape) into the
  database, replacing all existing content. Used by POST /api/reset,
  POST /api/seed, and first-boot seeding from `<data_dir>/seed.json`.

  A submitted round's per-question `answer` objects become BOTH the
  drafts and the frozen snapshot, so the migrated sprite reproduces the
  original /admin/answers output byte for byte (status, submitted_at and
  every answer field are carried verbatim). A withdrawn round's
  `last_snapshot` in the document is restored the same way.

  FREEZE GUARD: a load that would drop an existing submitted snapshot —
  a snapshotted round missing from the document, or present but neither
  submitted nor carrying its `last_snapshot` — is refused with
  {:error, {:would_drop_snapshot, [round_numbers]}}, unless
  `force: true` is passed. Rebuild-from-backup via /api/reset is exactly
  how a frozen round would otherwise vanish.
  """

  alias DecisionSprite.Content
  alias DecisionSprite.Domain
  alias DecisionSprite.Resources.{DesignDoc, Round}

  def load(state, opts \\ [])

  def load(state, opts) when is_map(state) do
    case dropped_snapshots(state) do
      [] ->
        do_load(state)

      dropped ->
        if Keyword.get(opts, :force, false),
          do: do_load(state),
          else: {:error, {:would_drop_snapshot, dropped}}
    end
  end

  defp dropped_snapshots(state) do
    incoming = state["rounds"] || []

    preserved =
      for r <- incoming,
          r["status"] == "submitted" or is_map(r["last_snapshot"]),
          into: MapSet.new() do
        r["n"]
      end

    Content.snapshot_rounds()
    |> Enum.reject(&MapSet.member?(preserved, &1))
    |> Enum.sort()
  end

  defp do_load(state) do
    design = state["design"] || %{}
    rounds = state["rounds"] || []

    DecisionSprite.Repo.transaction(fn ->
      Content.wipe!()

      DesignDoc
      |> Ash.Changeset.for_create(
        :create,
        %{
          version: design["version"] || 0,
          updated_at: design["updated_at"] || "",
          title: design["title"] || System.get_env("APP_TITLE"),
          sections: Content.normalize_sections(design["sections"] || [])
        },
        domain: Domain
      )
      |> Ash.create!()

      for r <- rounds do
        status = r["status"] || "open"

        round =
          Round
          |> Ash.Changeset.for_create(
            :create,
            %{
              n: r["n"],
              status: status,
              submitted_at: r["submitted_at"],
              anything_else: r["anything_else"],
              withdrawn_at: r["withdrawn_since"]
            },
            domain: Domain
          )
          |> Ash.create!()

        Content.create_questions(round, r["questions"] || [])

        cond do
          status == "submitted" ->
            snapshot = %{
              "anything_else" => r["anything_else"] || "",
              "questions" =>
                Map.new(r["questions"] || [], fn q ->
                  {q["id"], Content.normalize_answer(q["answer"] || %{})}
                end)
            }

            round
            |> Ash.Changeset.for_update(:update, %{submitted_snapshot: snapshot}, domain: Domain)
            |> Ash.update!()

          is_map(r["last_snapshot"]) ->
            round
            |> Ash.Changeset.for_update(
              :update,
              %{submitted_snapshot: snapshot_from_view(r["last_snapshot"])},
              domain: Domain
            )
            |> Ash.update!()

          true ->
            :ok
        end
      end

      :ok
    end)

    :ok
  end

  # The view shape (questions as a list) back to the stored map shape.
  defp snapshot_from_view(view) do
    %{
      "submitted_at" => view["submitted_at"],
      "anything_else" => view["anything_else"] || "",
      "questions" =>
        Map.new(view["questions"] || [], fn q ->
          {q["id"],
           %{"prompt" => q["prompt"], "answer" => Content.normalize_answer(q["answer"] || %{})}}
        end)
    }
  end

  @doc "First-boot seeding: load <data_dir>/seed.json when the DB has no rounds."
  def seed_if_empty! do
    if Content.rounds_count() == 0 do
      seed_path =
        Application.get_env(:decision_sprite, :seed_path) ||
          Path.join(DecisionSprite.Store.data_dir(), "seed.json")

      if File.exists?(seed_path) do
        state = seed_path |> File.read!() |> Jason.decode!()
        :ok = load(state)

        DecisionSprite.Observe.emit("app.seeded", "succeeded", %{
          rounds: length(state["rounds"] || [])
        })
      else
        DecisionSprite.Observe.emit("app.seeded", "skipped", %{reason: "no_seed_file"})
      end
    else
      DecisionSprite.Observe.emit("app.seeded", "skipped", %{reason: "already_seeded"})
    end

    :ok
  end
end
