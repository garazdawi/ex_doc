# Script to generate HTML fixture docs for Playwright layout tests.
# Run with: mix run assets/test/layout/generate_fixtures.exs

fixture_dir = Path.join([File.cwd!(), "assets", "test", "layout", "fixtures"])
File.rm_rf!(fixture_dir)
File.mkdir_p!(fixture_dir)

tmp_dir = Path.join(fixture_dir, "tmp")
File.mkdir_p!(tmp_dir)

src_path = Path.join(tmp_dir, "spec_test.erl")
ebin_dir = Path.join(tmp_dir, "ebin")
File.mkdir_p!(ebin_dir)

# Write an Erlang module with various spec patterns
File.write!(src_path, ~S"""
-module(spec_test).
-moduledoc("Module for testing spec rendering patterns.").
-export([
  simple_inline/2, with_types_section/2, equiv_simple/1, equiv_full/2,
  long_equiv/4, long_equiv_full/6,
  multi_clause/1, concrete_return/2,
  same_type_vars/2, complex_return/3,
  no_spec/1, ann_return/1,
  with_since/1, with_since_equiv/1, with_since_equiv_full/2,
  long_sig_with_since/5,
  deprecated_with_since/1
]).

%% Simple spec that should be inlined (< 80 chars)
-doc("Simple function with inlined spec.").
-spec simple_inline(binary(), non_neg_integer()) -> byte().
simple_inline(Subject, Pos) -> binary:at(Subject, Pos).

%% Spec with named variables in when clause -> Types section
-doc("Function with decomposed Types section.").
-spec with_types_section(Subject, Endianness) -> Unsigned when
    Subject :: binary(),
    Endianness :: big | little,
    Unsigned :: non_neg_integer().
with_types_section(Subject, _Endianness) -> binary:decode_unsigned(Subject).

%% Equiv function (simple)
-doc(#{equiv => equiv_full(X, [])}).
-spec equiv_simple(integer()) -> integer().
equiv_simple(X) -> equiv_full(X, []).

-doc("Full equiv target function.").
-spec equiv_full(integer(), list()) -> integer().
equiv_full(X, _Opts) -> X.

%% Long equiv line that should wrap
-doc(#{equiv => long_equiv_full(Module, Opts, State, Data, self(), [])}).
long_equiv(Module, Opts, State, Data) -> long_equiv_full(Module, Opts, State, Data, self(), []).

-doc("Long equiv target.").
-spec long_equiv_full(module(), list(), term(), term(), pid(), list()) -> no_return().
long_equiv_full(_Module, _Opts, _State, _Data, _Server, _Actions) -> exit(normal).

%% Multi-clause spec
-doc("Multi-clause function.").
-spec multi_clause(atom()) -> integer();
                  (integer()) -> atom().
multi_clause(X) when is_atom(X) -> 42;
multi_clause(X) when is_integer(X) -> ok.

%% Concrete return type
-doc("Function with concrete return.").
-spec concrete_return(binary(), non_neg_integer()) -> byte().
concrete_return(S, P) -> binary:at(S, P).

%% Same type variables that should be merged
-doc("Function with same-type variables.").
-spec same_type_vars(List1, List2) -> List3 when
    List1 :: [T],
    List2 :: [T],
    List3 :: [T],
    T :: term().
same_type_vars(L1, L2) -> L1 ++ L2.

%% Complex return type (>= 20 chars)
-doc("Function with complex return type.").
-spec complex_return(binary(), dynamic(), map()) ->
    {Result :: dynamic(), Acc :: dynamic(), binary()}.
complex_return(B, A, _D) -> {B, A, <<>>}.

%% No spec
-doc("Function without a spec.").
no_spec(X) -> X.

%% Annotated return type
-doc("Function with annotated return.").
-spec ann_return(Subject :: binary()) -> Result :: term().
ann_return(Subject) -> Subject.

%% Function with since annotation
-doc(#{since => <<"1.0">>}).
-doc("Function with since annotation.").
-spec with_since(term()) -> ok.
with_since(_X) -> ok.

%% Equiv with since annotations on both entries
-doc(#{since => <<"1.0">>, equiv => with_since_equiv_full(X, [])}).
-spec with_since_equiv(integer()) -> integer().
with_since_equiv(X) -> with_since_equiv_full(X, []).

-doc(#{since => <<"2.0">>}).
-doc("Equiv target with different since.").
-spec with_since_equiv_full(integer(), list()) -> integer().
with_since_equiv_full(X, _Opts) -> X.

%% Long signature with since annotation (tests annotation positioning)
-doc(#{since => <<"1.5">>}).
-doc("Function with long signature and since.").
-spec long_sig_with_since(Module :: module(), Opts :: list(), State :: term(), Data :: term(), Timeout :: timeout()) -> ok | {error, term()}.
long_sig_with_since(_M, _O, _S, _D, _T) -> ok.

%% Deprecated function with since
-doc(#{since => <<"0.5">>}).
-doc(#{deprecated => "Use with_since/1 instead"}).
-doc("Deprecated function.").
-spec deprecated_with_since(term()) -> ok.
deprecated_with_since(X) -> with_since(X).
""")

{:ok, :spec_test} =
  :compile.file(
    String.to_charlist(src_path),
    [:return_errors, :debug_info, outdir: String.to_charlist(ebin_dir)]
  )

true = Code.prepend_path(ebin_dir)
{:module, :spec_test} = :code.load_file(:spec_test)

config = [
  version: "1.0.0",
  project: "SpecTest",
  formatters: ["html"],
  output: Path.join(fixture_dir, "doc"),
  source_beam: ebin_dir,
  extras: [],
  proglang: :erlang
]

ExDoc.generate(config[:project], config[:version], [config[:source_beam]], config)

# Cleanup tmp
File.rm_rf!(tmp_dir)

IO.puts("Fixtures generated at #{Path.join(fixture_dir, "doc")}")
