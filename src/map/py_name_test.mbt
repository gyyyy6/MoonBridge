//! Python naming rules, pinned case by case.
//!
//! Every case here corresponds to a name that actually appears in the S1
//! corpus or to a rule a generated stub would otherwise violate.

///|
test "plain identifiers pass through" {
  assert_eq(@map.python_identifier("parse"), "parse")
  assert_eq(@map.python_identifier("to_string"), "to_string")
  assert_eq(@map.python_identifier("Json"), "Json")
  assert_eq(@map.python_identifier("_internal"), "_internal")
}

///|
test "keywords get a trailing underscore" {
  assert_eq(@map.python_identifier("class"), "class_")
  assert_eq(@map.python_identifier("None"), "None_")
  assert_eq(@map.python_identifier("lambda"), "lambda_")
  assert_eq(@map.python_identifier("from"), "from_")
}

///|
test "soft keywords are left alone" {
  // `match` and `case` are only keywords in a match statement, so a method
  // called `match` is legal Python and stays readable.
  assert_false(@map.is_python_keyword("match"))
  assert_false(@map.is_python_keyword("case"))
  assert_eq(@map.python_identifier("match"), "match")
}

///|
test "stub imports are not shadowed" {
  // A generated `class Any` would break every annotation in the file.
  assert_eq(@map.python_identifier("Any"), "Any_")
  assert_eq(@map.python_identifier("Optional"), "Optional_")
  assert_eq(@map.python_identifier("TypeVar"), "TypeVar_")
  assert_eq(@map.python_identifier("MoonObject"), "MoonObject_")
}

///|
test "punctuation becomes underscore" {
  assert_eq(@map.python_identifier("a-b"), "a_b")
  assert_eq(@map.python_identifier("a.b"), "a_b")
  assert_eq(@map.python_identifier("a b"), "a_b")
}

///|
test "leading digits are prefixed" {
  assert_eq(@map.python_identifier("9lives"), "n_9lives")
}

///|
test "empty name becomes a placeholder" {
  assert_eq(@map.python_identifier(""), "_")
}

///|
test "non-ascii letters are kept" {
  // Python 3 identifiers are Unicode, so a MoonBit name written in Chinese is
  // a valid Python name and must not be mangled.
  assert_eq(@map.python_identifier("解析"), "解析")
}

///|
test "module stems flatten package paths" {
  assert_eq(
    @map.module_stem("moonbitlang/core/json"),
    "moonbitlang__core__json",
  )
  assert_eq(
    @map.module_stem("moonbit-community/yaml"),
    "moonbit_community__yaml",
  )
  assert_eq(@map.module_stem("cli/diff"), "cli__diff")
  assert_eq(@map.module_stem("mizchi/admiral"), "mizchi__admiral")
  assert_eq(
    @map.stub_filename("moonbitlang/core/json"),
    "moonbitlang__core__json.pyi",
  )
}

///|
test "module stems are unique per package" {
  // Two packages differing only in separator style must not collide, or one
  // stub would silently overwrite another during generation.
  assert_false(
    @map.module_stem("a/b_c") == @map.module_stem("a-b/c"),
    msg="separator styles collapsed to the same stem",
  )
}
