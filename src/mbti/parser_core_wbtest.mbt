//! White-box tests for the type-expression half of the parser.
//!
//! These call the private `Parser` directly so each production can be tested in
//! isolation instead of only through a whole-file parse.

///|
fn parser_of(src : String) -> Parser {
  Parser::new(tokenize(src))
}

///|
fn plain(name : String) -> TypeExpr {
  Named(QName::plain(name), [])
}

///|
test "parse_type: bare name" {
  assert_eq(parser_of("Int").parse_type(), plain("Int"))
}

///|
test "parse_type: generic application" {
  assert_eq(
    parser_of("Array[Int]").parse_type(),
    Named(QName::plain("Array"), [plain("Int")]),
  )
  assert_eq(
    parser_of("Result[Int, String]").parse_type(),
    Named(QName::plain("Result"), [plain("Int"), plain("String")]),
  )
}

///|
test "parse_type: nested generic with optional element" {
  assert_eq(
    parser_of("Array[Int?]").parse_type(),
    Named(QName::plain("Array"), [Optional(plain("Int"))]),
  )
}

///|
test "parse_type: package-qualified name" {
  assert_eq(
    parser_of("@builtin.ToJson").parse_type(),
    Named(QName::qualified("@builtin", "ToJson"), []),
  )
}

///|
test "parse_type: Self and Self[T]" {
  assert_eq(parser_of("Self").parse_type(), SelfType([]))
  assert_eq(parser_of("Self[T]").parse_type(), SelfType([plain("T")]))
}

///|
test "parse_type: unit and tuple" {
  assert_eq(parser_of("Unit").parse_type(), Unit)
  assert_eq(parser_of("()").parse_type(), Unit)
  assert_eq(
    parser_of("(Int, String)").parse_type(),
    Tuple([plain("Int"), plain("String")]),
  )
  // A single parenthesised type is not a one-element tuple.
  assert_eq(parser_of("(Int)").parse_type(), plain("Int"))
}

///|
test "parse_type: function types with effects" {
  // (T) -> Bool raise?
  assert_eq(
    parser_of("(T) -> Bool raise?").parse_type(),
    Func([{ kind: Positional, name: None, ty: plain("T"), }], plain("Bool"), {
      raises: false,
      raises_may: true,
      no_raise: false,
      no_cancel: false,
      error: None,
    }),
  )
  // () -> Unit
  assert_eq(
    parser_of("() -> Unit").parse_type(),
    Func([], Unit, Effect::pure()),
  )
}

///|
test "parse_type: borrowed trait object" {
  assert_eq(parser_of("&Show").parse_type(), Borrowed(plain("Show")))
}

///|
test "parse_param: positional, optional and labeled" {
  assert_eq(parser_of("Int").parse_param(), {
    kind: Positional,
    name: None,
    ty: plain("Int"),
  })
  assert_eq(parser_of("msg? : StringView").parse_param(), {
    kind: Optional,
    name: Some("msg"),
    ty: plain("StringView"),
  })
  assert_eq(parser_of("loc~ : SourceLoc").parse_param(), {
    kind: Labeled,
    name: Some("loc"),
    ty: plain("SourceLoc"),
  })
}

///|
test "parse_param: optional postfix type is positional" {
  // `String?` is a positional parameter of optional type, not `String` named `?`.
  assert_eq(parser_of("String?").parse_param(), {
    kind: Positional,
    name: None,
    ty: Optional(plain("String")),
  })
}

///|
test "parse_effect: pure, raise, raise?, raise Error" {
  assert_eq(parser_of("").parse_effect(), Effect::pure())
  let raises = parser_of("raise").parse_effect()
  assert_eq(raises.is_pure(), false)
  assert_eq(raises.raises, true)
  assert_eq(raises.error, None)
  let may = parser_of("raise?").parse_effect()
  assert_eq(may.raises_may, true)
  assert_eq(may.raises, false)
  let typed = parser_of("raise JsonDecodeError").parse_effect()
  assert_eq(typed.raises, true)
  assert_eq(typed.error, Some(plain("JsonDecodeError")))
}

///|
test "parse_effect: noraise and nocancel combine with a plus" {
  let e = parser_of("noraise + nocancel").parse_effect()
  assert_eq(e.no_raise, true)
  assert_eq(e.no_cancel, true)
  assert_eq(e.is_pure(), false)
  let single = parser_of("nocancel").parse_effect()
  assert_eq(single.no_cancel, true)
  assert_eq(single.no_raise, false)
}

///|
test "parse_generics: plain, bounded and defaulted" {
  assert_eq(parser_of("[T]").parse_generics(), [
    { name: "T", bounds: [], default: None, },
  ])
  assert_eq(parser_of("[A : Compare + Show]").parse_generics(), [
    {
      name: "A",
      bounds: [QName::plain("Compare"), QName::plain("Show")],
      default: None,
    },
  ])
  assert_eq(parser_of("[T = Int]").parse_generics(), [
    { name: "T", bounds: [], default: Some(plain("Int")), },
  ])
  assert_eq(parser_of("").parse_generics(), [])
}
