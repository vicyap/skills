defmodule DecisionSprite.Token do
  @moduledoc """
  The admin bearer token. Lives in a 0600 file (path from the
  ADMIN_TOKEN_FILE env / app config, default `<data_dir>/.admin_token`).
  Generated on first boot if missing; an existing file is never
  overwritten (deploys pre-place the token they want).
  """

  def path do
    Application.get_env(:decision_sprite, :admin_token_file) ||
      Path.join(DecisionSprite.Store.data_dir(), ".admin_token")
  end

  def ensure! do
    p = path()

    unless File.exists?(p) do
      File.mkdir_p!(Path.dirname(p))
      tok = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      # Write via a temp file + rename so a partial token is never visible.
      tmp = p <> ".tmp"
      File.write!(tmp, tok)
      File.chmod!(tmp, 0o600)
      File.rename!(tmp, p)
    end

    :ok
  end

  def current do
    ensure!()
    path() |> File.read!() |> String.trim()
  end
end
