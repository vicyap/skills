defmodule DecisionSprite.Observe do
  @moduledoc """
  The one observability outlet (observability checklist, Next Time pattern).

  Every meaningful operation emits exactly one structured terminal record:
  a JSON line on stdout with a closed result vocabulary.

  NEVER pass answer content here (choice text, other_text, comments,
  anything_else) and never the admin token. Counts, ids and event names only.
  """

  @results ~w(succeeded failed skipped retried degraded unknown)

  @doc """
  Emit one record. `result` must be one of succeeded | failed | skipped |
  retried | degraded | unknown; anything else is coerced to "unknown".
  Fields must be counts/ids only — never user content.
  """
  def emit(event, result \\ "succeeded", fields \\ %{})

  def emit(event, result, fields) when is_binary(event) and is_map(fields) do
    result = if result in @results, do: result, else: "unknown"

    record =
      Map.merge(
        %{"ts" => now_iso(), "event" => event, "result" => result},
        Map.new(fields, fn {k, v} -> {to_string(k), v} end)
      )

    IO.puts(Jason.encode!(record))
    :ok
  end

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace_suffix("Z", "+00:00")
  end
end
