defmodule ExDoc.Formatter.MANTest do
  use ExUnit.Case, async: true

  alias ExDoc.Formatter.MAN.Templates

  @moduletag :tmp_dir

  defp parse!(markdown) do
    ExDoc.DocAST.parse!(markdown, "text/markdown",
      markdown_processor: {ExDoc.Markdown.Earmark, []}
    )
  end

  defp config(%{tmp_dir: tmp_dir} = _context) do
    [
      project: "Elixir",
      version: "1.0.1",
      formatters: ["man"],
      output: tmp_dir,
      source_beam: "test/tmp/beam",
      skip_undefined_reference_warnings_on: ["Warnings"]
    ]
  end

  defp config(context, config) when is_map(context) and is_list(config) do
    Keyword.merge(config(context), config)
  end

  defp generate(config) do
    source_beam = config[:source_beam] |> List.wrap()
    ExDoc.generate(config[:project], config[:version], source_beam, config)
  end

  test "generates man page files", %{tmp_dir: tmp_dir} = context do
    generate(config(context))

    assert File.regular?(tmp_dir <> "/CompiledWithDocs.3")
    assert File.regular?(tmp_dir <> "/CompiledWithDocs.Nested.3")
    assert File.regular?(tmp_dir <> "/CustomBehaviourOne.3")
    assert File.regular?(tmp_dir <> "/CustomBehaviourTwo.3")
    assert File.regular?(tmp_dir <> "/RandomError.3")
    assert File.regular?(tmp_dir <> "/CustomProtocol.3")
    assert File.regular?(tmp_dir <> "/Mix.Tasks.TaskWithDocs.1")
  end

  test "generates module pages with OTP-style structure", %{tmp_dir: tmp_dir} = context do
    generate(config(context))

    content = File.read!(tmp_dir <> "/CompiledWithDocs.3")

    assert content =~ ".TH CompiledWithDocs 3"
    assert content =~ "Elixir v1.0.1"
    assert content =~ ".SH NAME\nCompiledWithDocs \\- moduledoc"
    assert content =~ ".SH DESCRIPTION"
    assert content =~ ".SH FUNCTIONS"

    # OTP-style function entries: .LP/.B/.br/.RS/.RE
    assert content =~ ".LP\n.B\n\\fBexample\\fR"
    assert content =~ ".br\n.RS"
    assert content =~ ".RE"

    assert content =~ "Some example"
    assert content =~ "Use something else instead"
    assert content =~ "\\fIsince 1.3.0\\fR"
    assert content =~ "\\fImacro\\fR"
    assert content =~ "\\fB__struct__\\fR"
    assert content =~ "Some struct"
  end

  test "renders types and specs", %{tmp_dir: tmp_dir} = context do
    generate(config(context))

    content = File.read!(tmp_dir <> "/TypesAndSpecs.3")

    assert content =~ ".TH TypesAndSpecs 3"
    assert content =~ ".SH DATA TYPES"
    assert content =~ ".SH FUNCTIONS"

    # Attribute prefixes stripped
    assert content =~ "\\fBpublic(t) ::"
    assert content =~ "\\fBadd(integer(), opaque()) :: integer()\\fR"
    refute content =~ "@type"
    refute content =~ "@opaque"
    refute content =~ "@spec"

    # Opaque types hide their internals
    assert content =~ "\\fBopaque()\\fR"
    refute content =~ "opaque() ::"
  end

  test "generates task pages with section 1", %{tmp_dir: tmp_dir} = context do
    generate(config(context))

    content = File.read!(tmp_dir <> "/Mix.Tasks.TaskWithDocs.1")
    assert content =~ ".TH Mix.Tasks.TaskWithDocs 1"
    assert content =~ "\\- Very useful task"
  end

  test "generates extras only when man_section is set", %{tmp_dir: tmp_dir} = context do
    config =
      config(context,
        extras: [
          {"test/fixtures/README.md", [man_section: 7]},
          "test/fixtures/LICENSE"
        ]
      )

    generate(config)

    # README has man_section set
    assert File.regular?(tmp_dir <> "/readme.7")
    assert File.read!(tmp_dir <> "/readme.7") =~ ".TH readme 7"

    # LICENSE has no man_section, so no man page
    refute File.exists?(tmp_dir <> "/license.7")
  end

  test "man option controls which modules get man pages", %{tmp_dir: tmp_dir} = context do
    # :tasks - only tasks
    generate(config(context, man: :tasks))
    assert File.regular?(tmp_dir <> "/Mix.Tasks.TaskWithDocs.1")
    refute File.exists?(tmp_dir <> "/CompiledWithDocs.3")
  end

  test "stores generated content in .build.man", %{tmp_dir: tmp_dir} = context do
    generate(config(context))

    content = File.read!(tmp_dir <> "/.build.man")
    assert content =~ "CompiledWithDocs.3"
    assert content =~ "Mix.Tasks.TaskWithDocs.1"

    files =
      content
      |> String.split("\n", trim: true)
      |> Enum.map(&Path.join(tmp_dir, &1))

    for file <- files do
      assert File.exists?(file)
    end
  end

  describe "synopsis_text" do
    test "does not truncate on line breaks" do
      ast =
        parse!(
          "Functions for asynchronous and synchronous start of\nprocesses adhering to the OTP design principles."
        )

      assert Templates.synopsis_text(ast) ==
               "Functions for asynchronous and synchronous start of processes adhering to the OTP design principles"
    end

    test "takes the first sentence" do
      assert Templates.synopsis_text(parse!("First sentence. Second sentence.")) ==
               "First sentence"
    end

    test "returns full text when no period" do
      assert Templates.synopsis_text(parse!("No period here")) == "No period here"
    end
  end

  describe "doc_to_roff" do
    test "pre blocks inside list items use .nf/.fi" do
      roff =
        Templates.doc_to_roff(
          parse!("""
          - Item with code:

                some_code()

            More text.
          """)
        )

      assert roff =~ ".nf\nsome_code()\n.fi"
    end

    test "definition list with bold code" do
      roff =
        Templates.doc_to_roff(
          parse!("""
          - **`one_for_one`** - Only that child is affected.

          - **`one_for_all`** - All children are restarted.
          """)
        )

      assert roff =~ "one_for_one\n.RS 2"
      assert roff =~ "one_for_all\n.RS 2"
      refute roff =~ ".IP \\(bu"
    end

    test "definition list with plain code and escaped dash" do
      roff =
        Templates.doc_to_roff(
          parse!("""
          - `tag_name` \\- Description of the tag.

          - `other_tag` \\- Another description.
          """)
        )

      assert roff =~ "tag_name\n.RS 2"
      assert roff =~ "other_tag\n.RS 2"
      refute roff =~ ".IP \\(bu"
    end

    test "first paragraph in bullet item does not start with .PP" do
      roff =
        Templates.doc_to_roff(
          parse!("""
          - `--canonical`, `-n` - Indicate the preferred URL

          - `--formatter`, `-f` - Which formatters to use
          """)
        )

      # .IP should be immediately followed by the text, not .PP
      refute roff =~ ".IP \\(bu 2\n.PP\n"
      assert roff =~ ".IP \\(bu 2\n\\fI--canonical\\fR"

      # Second paragraph within the same item should still get .PP
      roff =
        Templates.doc_to_roff(
          parse!("""
          - First paragraph.

            Second paragraph.
          """)
        )

      assert roff =~ ".IP \\(bu 2\nFirst paragraph."
      assert roff =~ ".PP\nSecond paragraph."
    end

    test "plain code without dash is a regular bullet" do
      roff =
        Templates.doc_to_roff(
          parse!("""
          - `just_code` is used for something.

          - Another item.
          """)
        )

      assert roff =~ ".IP \\(bu 2"
    end

    test "strips m:, t:, c: prefixes from code" do
      roff = Templates.doc_to_roff(parse!("See `t:float/0` and `m:io` and `c:init/1`."))

      assert roff =~ "\\fIfloat/0\\fR"
      assert roff =~ "\\fIio\\fR"
      assert roff =~ "\\fIinit/1\\fR"
      refute roff =~ "t:float"
      refute roff =~ "m:io"
      refute roff =~ "c:init"
    end

    test "strips doc prefixes from bare text" do
      # Post-autolink AST where code nodes were replaced with plain text
      roff = Templates.doc_to_roff([{:p, [], ["is a t:float/0 and not a t:integer/0"], %{}}])

      assert roff =~ "is a float/0 and not a integer/0"
      refute roff =~ "t:float"
    end

    test "collapses blank lines from split text nodes" do
      # Post-autolink AST with split text nodes
      assert Templates.doc_to_roff([{:p, [], ["not an\n", "\n", "integer/0)"], %{}}]) =~
               "not an\ninteger/0)"

      roff =
        Templates.doc_to_roff([
          {:ul, [], [{:li, [], ["not an\n", "\n", "integer/0)"], %{}}], %{}}
        ])

      refute roff =~ "\n\n"
    end
  end

  describe "format_spec" do
    test "wraps each line individually in bold" do
      assert Templates.format_spec("add(a, b) :: c") == "\\fBadd(a, b) :: c\\fR"

      result = Templates.format_spec("foo(A) -> B\n    when A :: integer().")
      assert result == "\\fBfoo(A) -> B\\fR\n\\fB    when A :: integer().\\fR"
    end
  end

  describe "group_section_title" do
    test "maps Types to DATA TYPES" do
      assert Templates.group_section_title("Types") == "DATA TYPES"
      assert Templates.group_section_title(:Types) == "DATA TYPES"
    end

    test "uppercases other titles" do
      assert Templates.group_section_title("Functions") == "FUNCTIONS"
      assert Templates.group_section_title("Callbacks") == "CALLBACKS"
    end
  end
end
