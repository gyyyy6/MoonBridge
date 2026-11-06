//! Black-box tests for the `.mbti` lexer.
//!
//! These only use the package's public API, so they also prove that the token
//! surface is usable from outside the package.

///|
fn ident(s : String) -> @mbti.Tok {
  @mbti.Tok::Ident(s)
}

///|
fn punct(s : String) -> @mbti.Tok {
  @mbti.Tok::Punct(s)
}

///|
fn str(s : String) -> @mbti.Tok {
  @mbti.Tok::Str(s)
}

///|
fn num(n : Int32) -> @mbti.Tok {
  @mbti.Tok::Num(n)
}

///|
fn nl() -> @mbti.Tok {
  @mbti.Tok::Newline
}

///|
fn eof() -> @mbti.Tok {
  @mbti.Tok::Eof
}

///|
fn kinds(toks : Array[@mbti.Token]) -> Array[@mbti.Tok] {
  toks.map(fn(t) { t.kind })
}

///|
test "tokenize: simple function signature" {
  let toks = @mbti.tokenize("pub fn add(Int, Int) -> Int\n")
  assert_eq(kinds(toks), [
    ident("pub"),
    ident("fn"),
    ident("add"),
    punct("("),
    ident("Int"),
    punct(","),
    ident("Int"),
    punct(")"),
    punct("->"),
    ident("Int"),
    nl(),
    eof(),
  ])
}

///|
test "tokenize: drops comments but keeps the newline" {
  let toks = @mbti.tokenize("// Values\npub let x : Int\n")
  assert_eq(kinds(toks), [
    nl(),
    ident("pub"),
    ident("let"),
    ident("x"),
    punct(":"),
    ident("Int"),
    nl(),
    eof(),
  ])
}

///|
test "tokenize: attribute with nested parens and string argument" {
  let toks = @mbti.tokenize(
    "#label_migration(len, fill=false, msg=\"Use ArrayView::blit_to instead\")\n",
  )
  assert_eq(kinds(toks), [
    punct("#"),
    ident("label_migration"),
    punct("("),
    ident("len"),
    punct(","),
    ident("fill"),
    punct("="),
    ident("false"),
    punct(","),
    ident("msg"),
    punct("="),
    str("Use ArrayView::blit_to instead"),
    punct(")"),
    nl(),
    eof(),
  ])
}

///|
test "tokenize: escapes inside string literals" {
  assert_eq(kinds(@mbti.tokenize("\"a\\\"b\"")), [str("a\"b"), eof()])
  assert_eq(kinds(@mbti.tokenize("\"tab\\there\"")), [str("tab\there"), eof()])
}

///|
test "tokenize: non-ASCII bytes stay inside identifiers" {
  let toks = @mbti.tokenize("pub fn 求和(Int) -> Int\n")
  assert_eq(kinds(toks), [
    ident("pub"),
    ident("fn"),
    ident("求和"),
    punct("("),
    ident("Int"),
    punct(")"),
    punct("->"),
    ident("Int"),
    nl(),
    eof(),
  ])
}

///|
test "tokenize: arrow and dot tokens" {
  let toks = @mbti.tokenize("(A) -> B .. c")
  assert_eq(kinds(toks), [
    punct("("),
    ident("A"),
    punct(")"),
    punct("->"),
    ident("B"),
    punct(".."),
    ident("c"),
    eof(),
  ])
}

///|
test "tokenize: tracks line and column" {
  let toks = @mbti.tokenize("pub\n  fn")
  assert_eq(toks[0].line, 1)
  assert_eq(toks[0].col, 1)
  assert_eq(toks[1].kind, nl())
  assert_eq(toks[2].line, 2)
  assert_eq(toks[2].col, 3)
}

///|
test "tokenize: numbers" {
  assert_eq(kinds(@mbti.tokenize("16 0 2026")), [
    num(16),
    num(0),
    num(2026),
    eof(),
  ])
}

///|
test "tokenize: empty input yields just EOF" {
  assert_eq(kinds(@mbti.tokenize("")), [eof()])
}
