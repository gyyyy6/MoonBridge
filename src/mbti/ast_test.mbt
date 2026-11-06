//! Tests for AST helper functions.

///|
fn named(name : String, args : Array[@mbti.TypeExpr]) -> @mbti.TypeExpr {
  @mbti.TypeExpr::Named(@mbti.QName::plain(name), args)
}

///|
test "QName renders package qualification" {
  assert_eq(@mbti.QName::plain("Array").to_string(), "Array")
  assert_eq(
    @mbti.QName::qualified("@builtin", "ToJson").to_string(),
    "@builtin.ToJson",
  )
}

///|
test "TypeExpr collects nested names including generic arguments" {
  // Array[@builtin.Json] -> ["Array", "@builtin.Json"]
  let te = named("Array", [named("@builtin.Json", [])])
  let out : Array[@mbti.QName] = []
  te.collect_names(out)
  assert_eq(out.map(fn(q) { q.to_string() }), ["Array", "@builtin.Json"])
}

///|
test "TypeExpr collects names from function types and effects" {
  // (T) -> Result[Int, MyError] raise MyError
  let te = @mbti.TypeExpr::Func(
    [{ kind: Positional, name: None, ty: named("T", []), }],
    named("Result", [named("Int", []), named("MyError", [])]),
    {
      raises: true,
      raises_may: false,
      no_raise: false,
      no_cancel: false,
      error: Some(named("MyError", [])),
    },
  )
  let out : Array[@mbti.QName] = []
  te.collect_names(out)
  assert_eq(out.map(fn(q) { q.to_string() }), [
    "T", "Result", "Int", "MyError", "MyError",
  ])
}

///|
test "TypeExpr head_name ignores arguments" {
  assert_eq(named("Map", [named("K", []), named("V", [])]).head_name(), "Map")
  assert_eq(@mbti.TypeExpr::Optional(named("Int", [])).head_name(), "Option")
  assert_eq(@mbti.TypeExpr::Unit.head_name(), "Unit")
}

///|
test "Decl kind_name and declared_name" {
  let struct_decl = @mbti.Decl::Struct({
    name: "Point",
    generics: [],
    fields: [],
    has_hidden_fields: false,
    derives: [],
    attrs: [],
    access: Open,
  })
  assert_eq(struct_decl.kind_name(), "struct")
  assert_eq(struct_decl.declared_name(), Some("Point"))

  let impl_decl = @mbti.Decl::Impl({
    trait_name: @mbti.QName::plain("Eq"),
    trait_args: [],
    for_ty: named("Point", []),
    attrs: [],
  })
  assert_eq(impl_decl.kind_name(), "impl")
  assert_eq(impl_decl.declared_name(), None)
}

///|
test "Package counts declarations by kind" {
  let pkg = @mbti.Package::{
    name: "demo",
    imports: [],
    decls: [
      @mbti.Decl::Opaque({
        name: "Buffer",
        generics: [],
        derives: [],
        access: Private,
        attrs: [],
      }),
      @mbti.Decl::Opaque({
        name: "Reader",
        generics: [],
        derives: [],
        access: Private,
        attrs: [],
      }),
      @mbti.Decl::Impl({
        trait_name: @mbti.QName::plain("Show"),
        trait_args: [],
        for_ty: named("Buffer", []),
        attrs: [],
      }),
    ],
  }
  assert_eq(pkg.count_kind("type"), 2)
  assert_eq(pkg.count_kind("impl"), 1)
  assert_eq(pkg.count_kind("enum"), 0)
}
