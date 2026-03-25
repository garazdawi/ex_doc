defmodule ExDoc.Formatter.ErlangTest do
  use ExUnit.Case, async: true
  import TestHelper

  @moduletag :tmp_dir

  @tag :otp_eep48
  test "EEP 48", c do
    erlc(c, :foo, ~S"""
    %% @doc
    %% foo module.
    -module(foo).
    -export([foo/1, bar/0]).
    -export_type([t/0, t2/0]).

    %% @doc
    %% f/0 function.
    -spec foo(t()) -> t().
    foo(X) -> X.

    -spec bar() -> baz.
    bar() -> baz.

    -type t() :: atom().
    %% t/0 type.

    -record(rec, {k1 :: any(), k2 :: any()}).

    -type t2() :: #rec{k1 :: uri_string:uri_string(), k2 :: uri_string:uri_string() | undefined}.
    """)

    generate(c)
    html = c.tmp_dir |> Path.join("doc/foo.html") |> File.read!()

    # Check simple specs are inlined in the signature with autolinks
    assert html =~ ~s|<a href="#t:t/0">t</a>()|

    # Check types are rendered with proper links in HTML

    assert html =~
             ~s|-type</span> t2() :: #rec{k1 :: <a href="https://www.erlang.org/doc/apps/stdlib/uri_string.html#t:uri_string/0">uri_string:uri_string</a>(), k2 :: <a href="https://www.erlang.org/doc/apps/stdlib/uri_string.html#t:uri_string/0">uri_string:uri_string</a>() \| undefined}.|

    # EEP 48 uses erlang+html format, so no markdown should be generated
    refute File.exists?(Path.join(c.tmp_dir, "doc/foo.md"))
  end

  @tag :otp_eep59
  test "EEP 59", c do
    erlc(c, :bar, ~S"""
    -module(bar).
    -moduledoc("bar module.").
    -export([bar/1, baz/0]).
    -export_type([t/0, o/0]).

    -doc("bar/1 function.").
    -spec bar(t()) -> t().
    bar(X) -> X.

    -doc("baz/0 function.").
    -spec baz() -> atom().
    baz() -> ok.

    -doc("t/0 type.").
    -type t() :: atom().

    -doc("o/0 opaque.").
    -opaque o() :: {atom(), integer()}.
    """)

    generate(c)
    html = c.tmp_dir |> Path.join("doc/bar.html") |> File.read!()

    # Check moduledoc is rendered in HTML
    assert html =~ "<p>bar module.</p>"

    # Check function docs are rendered in HTML
    assert html =~ "<p>bar/1 function.</p>"
    assert html =~ "<p>baz/0 function.</p>"

    # Check simple specs are inlined in the signature with autolinks
    assert html =~ ~s|<a href="#t:t/0">t</a>()|

    # Check type is rendered with proper links in HTML
    assert html =~
             ~s|-type</span> t() :: <a href="https://www.erlang.org/doc/apps/erts/erlang.html#t:atom/0">atom</a>().|

    # Check type doc is rendered in HTML
    assert html =~ "<p>t/0 type.</p>"

    # EEP 59 uses text/markdown format, so markdown should be generated
    markdown = c.tmp_dir |> Path.join("doc/bar.md") |> File.read!()

    # Check moduledoc in markdown
    assert markdown =~ "bar module."

    # Check function docs in markdown
    assert markdown =~ "bar/1 function."
    assert markdown =~ "baz/0 function."

    # Check specs in markdown (markdown doesn't go through autolink, uses raw format)
    assert markdown =~ "```erlang\n-spec bar(t()) -> t()."
    assert markdown =~ "```erlang\n-spec baz() -> atom()."

    # Check type in markdown
    assert markdown =~ "```erlang\n-type t() :: atom()."
    assert markdown =~ "t/0 type."

    # Opaque types hide their internals in both HTML and markdown
    assert html =~ ~s|-opaque</span> o()|
    refute html =~ ~s|o() :: {|
    assert markdown =~ "```erlang\n-opaque o()\n```"
    refute markdown =~ "o() ::"
    assert markdown =~ "o/0 opaque."
  end

  @tag :otp_eep59
  test "spec rendering styles", c do
    erlc(c, :spec_mod, ~S"""
    -module(spec_mod).
    -moduledoc("spec module.").
    -export([inlined/2, decomposed/2, multi_clause/1, stripped/3]).

    -doc("Inlined spec.").
    -spec inlined(binary(), non_neg_integer()) -> byte().
    inlined(S, P) -> binary:at(S, P).

    -doc("Decomposed spec.").
    -spec decomposed(Subject, Endianness) -> Unsigned when
        Subject :: binary(),
        Endianness :: big | little | {custom, binary()},
        Unsigned :: non_neg_integer().
    decomposed(S, _E) -> binary:decode_unsigned(S).

    -doc("Multi-clause spec.").
    -spec multi_clause(atom()) -> integer(); (integer()) -> atom().
    multi_clause(X) when is_atom(X) -> 42;
    multi_clause(X) when is_integer(X) -> ok.

    -doc("Stripped signature.").
    stripped(_, _, _) -> ok.
    """)

    generate(c, :spec_mod)
    html = c.tmp_dir |> Path.join("doc/spec_mod.html") |> File.read!()

    # Inlined spec: types shown in signature with links
    assert html =~ ~s|inlined(S :: |

    assert html =~
             ~s|<a href="https://www.erlang.org/doc/apps/erts/erlang.html#t:byte/0">byte</a>()|

    # Decomposed spec: Types section with heading
    assert html =~ ~s|<h4 class="specs-title">Types</h4>|
    assert html =~ ~s|Subject = |
    assert html =~ ~s|Unsigned = |

    # Decomposed spec: signature includes return type
    assert html =~ ~s|decomposed(Subject, Endianness)|
    assert html =~ ~s|Unsigned|

    # Multi-clause spec: falls back to -spec rendering
    assert html =~ ~s|-spec</span> multi_clause|

    # Stripped signature: falls back to -spec rendering
    assert html =~ ~s|stripped/3|
  end

  @tag :otp_eep59
  test "equiv merged functions", c do
    erlc(c, :equiv_mod, ~S"""
    -module(equiv_mod).
    -moduledoc("equiv module.").
    -export([foo/1, foo/2]).

    -doc(#{equiv => foo(X, [])}).
    -spec foo(integer()) -> integer().
    foo(X) -> foo(X, []).

    -doc("foo/2 docs.").
    -spec foo(integer(), list()) -> integer().
    foo(X, _Opts) -> X.
    """)

    generate(c, :equiv_mod)
    html = c.tmp_dir |> Path.join("doc/equiv_mod.html") |> File.read!()

    # Equiv entry shown with ≡ marker
    assert html =~ "≡"

    # Both signatures present
    assert html =~ "foo(X)"
    assert html =~ "foo(X, Opts)"

    # Equiv anchor exists
    assert html =~ ~s|id="foo/1"|

    # Main section uses foo/2 as the primary ID
    assert html =~ ~s|id="foo/2"|

    # Summary shows both entries
    assert html =~ ~s|<a href="#foo/1"|
    assert html =~ ~s|<a href="#foo/2"|
  end

  defp generate(c, _module \\ nil) do
    config = [
      version: "1.0.0",
      project: "Foo",
      formatters: ["html", "markdown"],
      output: Path.join(c.tmp_dir, "doc"),
      source_beam: Path.join(c.tmp_dir, "ebin"),
      extras: []
    ]

    ExDoc.generate(config[:project], config[:version], [config[:source_beam]], config)
  end
end
