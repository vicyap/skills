defmodule DecisionSpriteWeb.PageController do
  use DecisionSpriteWeb, :controller

  alias DecisionSprite.{Content, Markdown}

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  defp esc(v), do: v |> html_escape() |> safe_to_string()
  defp raw_md(body), do: Markdown.to_html(body || "")

  def design(conn, _params) do
    title = Content.app_title()
    d = Content.design()
    view = Content.answers_view()

    sections_html =
      case d do
        nil ->
          ""

        _ ->
          Content.normalize_sections(d.sections)
          |> Enum.map_join("\n", fn s ->
            eyebrow = s["status"] || "Design"

            """
            <section class="card">
              <p class="eyebrow">#{esc(eyebrow)}</p>
              <h2 class="headline">#{esc(s["heading"])}</h2>
              <div class="body">#{raw_md(s["body"])}</div>
            </section>
            """
          end)
      end

    meta =
      case d do
        nil ->
          ""

        _ ->
          ~s(<p class="mono meta">Design v#{d.version} · updated #{esc(String.slice(d.updated_at || "", 0, 16) |> String.replace("T", " "))}</p>)
      end

    submitted = Enum.filter(view["rounds"], &(&1["status"] == "submitted"))

    answers_html =
      if submitted == [] do
        ""
      else
        items =
          Enum.map_join(submitted, "\n", fn r ->
            qs =
              Enum.map_join(r["questions"], "\n", fn q ->
                a = q["answer"] || %{}
                label = a["choice_label"] || ""
                label = if label == "", do: "(no option picked)", else: label

                extra =
                  ""
                  |> Kernel.<>(
                    if(a["other_text"] not in [nil, ""],
                      do: "<br>Other: #{esc(a["other_text"])}",
                      else: ""
                    )
                  )
                  |> Kernel.<>(
                    if(a["comment"] not in [nil, ""],
                      do: ~s(<br><span class="mut">Comment:</span> ) <> esc(a["comment"]),
                      else: ""
                    )
                  )

                """
                <div class="ans"><span class="who">#{esc(q["prompt"])}</span><br><strong>#{esc(label)}</strong>#{extra}</div>
                """
              end)

            anything =
              if r["anything_else"] not in [nil, ""] do
                ~s(<div class="ans"><span class="who">Anything else</span><br>#{esc(r["anything_else"])}</div>)
              else
                ""
              end

            date = String.slice(r["submitted_at"] || "", 0, 10)
            "<h3>Round #{r["n"]} · #{esc(date)}</h3>" <> qs <> anything
          end)

        """
        <section class="card">
          <p class="eyebrow">Record</p>
          <h2 class="headline">Your answers so far</h2>
          #{items}
        </section>
        """
      end

    open_round = Enum.find(Content.rounds(), &(&1.status == "open"))

    open_html =
      if open_round do
        ~s(<p><a class="round-link" href="/questions">Round #{open_round.n} is waiting for your decisions →</a></p>)
      else
        ""
      end

    body = """
    <div class="wrap">
      <header class="top">
        <p class="eyebrow">Decision session with Muse</p>
        <h1 class="app-title">#{esc(title)}</h1>
        <p class="sub">Your answers are saved word for word and shape what gets built.</p>
      </header>
      <nav class="tabs">
        <a href="/" class="on">The design</a>
        <a href="/questions">Decisions</a>
      </nav>
      #{meta}
      #{sections_html}
      #{answers_html}
      #{open_html}
    </div>
    """

    html(conn, document(title, body))
  end

  defp document(title, body) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(title)}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Albert+Sans:wght@200;300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
      <link rel="stylesheet" href="/app.css">
    </head>
    <body>
    #{body}
    </body>
    </html>
    """
  end
end
