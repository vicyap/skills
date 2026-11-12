defmodule DecisionSprite.Repo do
  use AshSqlite.Repo, otp_app: :decision_sprite

  # The SQLite library exqlite bundles (and every release ships) is
  # 3.54.1; declare it so ecto_sqlite3 doesn't assume the lowest
  # compatible version and warn at compile time.
  def min_sqlite_version do
    %Version{major: 3, minor: 54, patch: 1}
  end
end
