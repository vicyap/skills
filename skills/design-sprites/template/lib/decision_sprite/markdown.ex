defmodule DecisionSprite.Markdown do
  @moduledoc """
  The same tiny markdown subset as the Python sprites: paragraphs,
  "- " lists, **bold**, ### and ## headings. Everything is HTML-escaped
  first; output is marked safe for templates.
  """

  def to_html(nil), do: ""

  def to_html(text) when is_binary(text) do
    {out, in_list} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn raw, {out, in_list} ->
        line = String.trim(raw)

        cond do
          String.starts_with?(line, "- ") ->
            out = if in_list, do: out, else: out ++ ["<ul>"]
            {out ++ ["<li>" <> inline(String.slice(line, 2..-1//1)) <> "</li>"], true}

          true ->
            out = if in_list, do: out ++ ["</ul>"], else: out

            cond do
              line == "" ->
                {out, false}

              String.starts_with?(line, "### ") ->
                {out ++ ["<h3>" <> inline(String.slice(line, 4..-1//1)) <> "</h3>"], false}

              String.starts_with?(line, "## ") ->
                {out ++ ["<h2>" <> inline(String.slice(line, 3..-1//1)) <> "</h2>"], false}

              true ->
                {out ++ ["<p>" <> inline(line) <> "</p>"], false}
            end
        end
      end)

    out = if in_list, do: out ++ ["</ul>"], else: out
    Enum.join(out, "\n")
  end

  defp inline(s) do
    s
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> bold()
  end

  # Replace ** pairs with <strong>/</strong> in order, like the Python app.
  defp bold(s) do
    s
    |> String.split("**")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, 0} -> part
      {part, i} when rem(i, 2) == 1 -> "<strong>" <> part
      {part, _i} -> "</strong>" <> part
    end)
    |> Enum.join("")
  end
end
