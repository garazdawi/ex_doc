defmodule ExDoc.Formatter.MAN.Templates do
  @moduledoc false

  require EEx

  @doc """
  Converts a doc AST node to roff-formatted text.
  """
  def doc_to_roff(nil), do: ""
  def doc_to_roff(ast) when is_list(ast), do: Enum.map_join(ast, &doc_to_roff/1)
  def doc_to_roff(binary) when is_binary(binary), do: binary |> strip_prefix() |> escape()

  def doc_to_roff({:comment, _attrs, _inner, _meta}), do: ""

  def doc_to_roff({:p, _attrs, inner, _meta}) do
    text = inner |> inline() |> String.replace(~r/\n{2,}/, "\n")
    ".PP\n#{text}\n"
  end

  def doc_to_roff({tag, _attrs, inner, _meta})
      when tag in [:h1, :h2, :h3, :h4, :h5, :h6] do
    ".SS \"#{inline(inner)}\"\n"
  end

  def doc_to_roff({:pre, _attrs, [{:code, _, [code], _}], _meta}) when is_binary(code) do
    ".IP\n.nf\n#{escape(code)}\n.fi\n"
  end

  def doc_to_roff({:pre, _attrs, inner, _meta}) do
    ".IP\n.nf\n#{inline(inner)}\n.fi\n"
  end

  def doc_to_roff({:blockquote, _attrs, inner, _meta}) do
    ".RS 4\n#{doc_to_roff(inner)}.RE\n"
  end

  def doc_to_roff({:ul, _attrs, items, _meta}) do
    Enum.map_join(items, &render_li/1)
  end

  def doc_to_roff({:ol, _attrs, items, _meta}) do
    items
    |> Enum.with_index(1)
    |> Enum.map_join(fn {{:li, _attrs, inner, _meta}, idx} ->
      ".IP #{idx}. 3\n#{render_li_body(inner)}"
    end)
  end

  def doc_to_roff({:dl, _attrs, inner, _meta}) do
    Enum.map_join(inner, fn
      {:dt, _attrs, inner, _meta} -> ".TP\n\\fB#{inline(inner)}\\fR\n"
      {:dd, _attrs, inner, _meta} -> doc_to_roff(inner)
    end)
  end

  def doc_to_roff({:table, _attrs, inner, _meta}), do: doc_to_roff(inner)
  def doc_to_roff({:thead, _attrs, inner, _meta}), do: doc_to_roff(inner)
  def doc_to_roff({:tbody, _attrs, inner, _meta}), do: doc_to_roff(inner)

  def doc_to_roff({:tr, _attrs, cells, _meta}) do
    text = Enum.map_join(cells, " | ", fn {_tag, _attrs, inner, _meta} -> inline(inner) end)
    ".PP\n#{text}\n"
  end

  def doc_to_roff({:hr, _attrs, _inner, _meta}), do: ""
  def doc_to_roff({:section, _attrs, inner, _meta}), do: doc_to_roff(inner)
  def doc_to_roff({_tag, _attrs, inner, _meta}), do: doc_to_roff(inner)

  ## List items

  defp render_li({:li, _attrs, inner, _meta}) do
    case detect_deflist(inner) do
      {:deflist, tag, rest} ->
        "\n#{escape(tag)}\n.RS 2\n#{render_li_body(rest)}.RE\n"

      :regular ->
        ".IP \\(bu 2\n#{render_li_body(inner)}"
    end
  end

  # Detects definition list items: `tag` \- desc or **`tag`** - desc.
  # Returns {:deflist, tag, rest} or :regular.
  defp detect_deflist([{:p, p_attrs, [head | rest], p_meta} | tail]) do
    with {:ok, tag} <- extract_code_tag(head),
         stripped when stripped != rest <- strip_dash_prefix(rest) do
      {:deflist, tag, [{:p, p_attrs, stripped, p_meta} | tail]}
    else
      _ -> :regular
    end
  end

  defp detect_deflist([head | rest]) do
    with {:ok, tag} <- extract_code_tag(head),
         stripped when stripped != rest <- strip_dash_prefix(rest) do
      {:deflist, tag, stripped}
    else
      _ -> :regular
    end
  end

  defp detect_deflist(_), do: :regular

  defp extract_code_tag({:strong, _, [{:code, _, [tag], _}], _}) when is_binary(tag),
    do: {:ok, tag}

  defp extract_code_tag({:code, _, [tag], _}) when is_binary(tag), do: {:ok, tag}
  defp extract_code_tag(_), do: :error

  defp strip_dash_prefix([text | rest]) when is_binary(text) do
    case String.replace(text, ~r/^\s*\\?-\s*/, "", global: false) do
      "" -> rest
      trimmed -> [trimmed | rest]
    end
  end

  defp strip_dash_prefix(content), do: content

  defp render_li_body(inner) when is_list(inner) do
    {body, _} =
      Enum.map_reduce(inner, true, fn
        binary, first? when is_binary(binary) -> {inline(binary), first?}
        {:p, _attrs, content, _meta}, true -> {inline(content), false}
        {:p, _attrs, content, _meta}, false -> {".PP\n#{inline(content)}", false}
        other, _first? -> {doc_to_roff(other), false}
      end)

    body = body |> IO.iodata_to_binary() |> String.replace(~r/\n{2,}/, "\n")
    if String.ends_with?(body, "\n"), do: body, else: body <> "\n"
  end

  ## Inline rendering

  @doc """
  Renders inline AST content to roff.
  """
  def inline(list) when is_list(list), do: Enum.map_join(list, &inline/1)
  def inline(binary) when is_binary(binary), do: binary |> strip_prefix() |> escape()

  def inline({:comment, _attrs, _inner, _meta}), do: ""

  def inline({:code, _attrs, [code], _meta}) when is_binary(code),
    do: "\\fI#{code |> strip_prefix() |> escape()}\\fR"

  def inline({:strong, _attrs, inner, _meta}), do: "\\fB#{inline(inner)}\\fR"
  def inline({:b, _attrs, inner, _meta}), do: "\\fB#{inline(inner)}\\fR"
  def inline({:em, _attrs, inner, _meta}), do: "\\fI#{inline(inner)}\\fR"
  def inline({:i, _attrs, inner, _meta}), do: "\\fI#{inline(inner)}\\fR"
  def inline({:br, _attrs, _inner, _meta}), do: "\n.br\n"
  def inline({:a, _attrs, inner, _meta}), do: inline(inner)
  def inline({_tag, _attrs, inner, _meta}), do: inline(inner)

  ## Text processing

  # Strips m:, t:, c: doc reference prefixes.
  # At start of text (code nodes) or at word boundaries (plain text after autolinking).
  defp strip_prefix(text) do
    String.replace(text, ~r/\b[mtc]:(\w)/, "\\1")
  end

  @doc """
  Formats a spec for man page output.
  Wraps each line individually in bold.
  """
  def format_spec(spec_text) do
    spec_text
    |> escape()
    |> String.split("\n")
    |> Enum.map_join("\n", &"\\fB#{&1}\\fR")
  end

  @doc """
  Escapes text for roff output.
  """
  def escape(text) do
    String.replace(text, "\\", "\\\\")
  end

  @doc """
  Extracts a short synopsis from the doc AST for the NAME section.
  """
  def synopsis_text(nil), do: nil

  def synopsis_text(ast) when is_list(ast) do
    Enum.find_value(ast, fn
      {:comment, _, _, _} -> nil
      node -> synopsis_text(node)
    end)
  end

  def synopsis_text({:p, _attrs, inner, _meta}) do
    inner
    |> ExDoc.DocAST.text()
    |> String.replace("\n", " ")
    |> String.split(~r/\.(\s|$)/, parts: 2)
    |> hd()
    |> String.trim()
  end

  def synopsis_text(_), do: nil

  @doc """
  Returns the section title for a doc group, uppercased for .SH headers.
  """
  def group_section_title("Types"), do: "DATA TYPES"
  def group_section_title(title) when is_atom(title), do: group_section_title(to_string(title))
  def group_section_title(title) when is_binary(title), do: String.upcase(title)

  ## EEx templates

  EEx.function_from_file(
    :def,
    :module_template,
    Path.expand("templates/module_template.eex", __DIR__),
    [:config, :module],
    trim: true
  )

  EEx.function_from_file(
    :def,
    :extra_template,
    Path.expand("templates/extra_template.eex", __DIR__),
    [:config, :extra, :section],
    trim: true
  )

  EEx.function_from_file(
    :defp,
    :detail_template,
    Path.expand("templates/detail_template.eex", __DIR__),
    [:node, :module],
    trim: true
  )
end
