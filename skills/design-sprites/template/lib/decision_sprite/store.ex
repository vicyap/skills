defmodule DecisionSprite.Store do
  @moduledoc """
  SQLite schema bootstrap. Idempotent CREATE TABLE IF NOT EXISTS on boot,
  following the house pattern (temi-glp1 / forget-me-not): the deploy
  artifact never carries data; the SQLite file lives in the data dir.
  Ash resources map these tables 1:1. `DecisionSprite.Release.migrate/0`
  runs this same DDL, so `run.sh`'s migrate step and app boot agree.
  """

  alias DecisionSprite.Repo

  def data_dir do
    Application.get_env(:decision_sprite, :data_dir) ||
      System.get_env("DATA_DIR") || "/data"
  end

  @tables [
    """
    CREATE TABLE IF NOT EXISTS design_docs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT '',
      title TEXT,
      sections TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS rounds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      n INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'open',
      submitted_at TEXT,
      anything_else TEXT,
      submitted_snapshot TEXT,
      withdrawn_at TEXT,
      draft_revision INTEGER NOT NULL DEFAULT 0
    )
    """,
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_rounds_n ON rounds(n)",
    """
    CREATE TABLE IF NOT EXISTS submission_notices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      round_n INTEGER NOT NULL,
      submitted_at TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      sent_at TEXT,
      acked_at TEXT,
      created_at TEXT,
      updated_at TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_notices_round ON submission_notices(round_n)",
    """
    CREATE TABLE IF NOT EXISTS health_probes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      token TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS questions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      round_id INTEGER NOT NULL REFERENCES rounds(id),
      qid TEXT NOT NULL,
      prompt TEXT NOT NULL,
      context TEXT,
      options TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      choice TEXT,
      choice_label TEXT,
      other_text TEXT,
      comment TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_questions_round ON questions(round_id)"
  ]

  def ensure_schema! do
    File.mkdir_p!(data_dir())

    for sql <- @tables do
      Ecto.Adapters.SQL.query!(Repo, sql)
    end

    # Columns added after the first release: CREATE TABLE IF NOT EXISTS
    # does not retrofit them onto an existing database, so add any that
    # are missing (idempotent, checked via PRAGMA).
    add_column_if_missing("rounds", "withdrawn_at", "TEXT")
    add_column_if_missing("rounds", "draft_revision", "INTEGER NOT NULL DEFAULT 0")

    :ok
  end

  defp add_column_if_missing(table, column, type) do
    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, "PRAGMA table_info(#{table})")
    columns = Enum.map(rows, &Enum.at(&1, 1))

    unless column in columns do
      Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
    end

    :ok
  end

  @doc """
  Health probe: a real write + read + delete round trip against the
  database (observability checklist §4 — /health must mean something).
  Returns true only when the value read back matches the value written.
  """
  def health_probe do
    token = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    Ecto.Adapters.SQL.query!(Repo, "INSERT INTO health_probes (token) VALUES (?1)", [token])

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(Repo, "SELECT token FROM health_probes WHERE token = ?1", [token])

    Ecto.Adapters.SQL.query!(Repo, "DELETE FROM health_probes WHERE token = ?1", [token])

    rows == [[token]]
  rescue
    _ -> false
  end
end
