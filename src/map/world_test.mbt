//! Tests for the cross-package index and the links it enables.
//!
//! The fixtures are hand-built ASTs rather than parsed interfaces: the point
//! here is the resolution rules, and a two-line package makes each rule
//! visible without a 600-line `.mbti` in the middle.

///|
fn pkg_of(
  name : String,
  imports : Array[String],
  decls : Array[@mbti.Decl],
) -> @mbti.Package {
  { name, imports, decls, }
}

///|

///|
/// A bare type name. Written as its own helper because a parameter whose type
/// is `Option[String]` reads as an optional parameter in MoonBit and silently
/// changes the function's arity.
fn plain(name : String) -> @mbti.TypeExpr {
  @mbti.TypeExpr::Named({ pkg: None, name, }, [])
}

///|
/// `@alias.Name`.
fn qualified(at : String, name : String) -> @mbti.TypeExpr {
  @mbti.TypeExpr::Named({ pkg: Some(at), name, }, [])
}

///|
fn field_of(name : String, ty : @mbti.TypeExpr) -> @mbti.Field {
  { name, ty, access: @mbti.Open, is_mut: false, label: None, }
}

///|
fn struct_of(name : String, fields : Array[@mbti.Field]) -> @mbti.Decl {
  @mbti.Decl::Struct({
    name,
    generics: [],
    fields,
    has_hidden_fields: false,
    derives: [],
    attrs: [],
    access: @mbti.Open,
  })
}

///|
fn fn_of(
  name : String,
  receiver : @mbti.QName?,
  ret : @mbti.TypeExpr,
) -> @mbti.Decl {
  @mbti.Decl::Func({
    name,
    is_async: false,
    receiver,
    generics: [],
    params: [],
    ret,
    effect: @mbti.Effect::pure(),
    attrs: [],
    access: @mbti.Open,
  })
}

///|
test "an import alias resolves to the full package path" {
  // `.mbti` writes `@json.Json` but imports `"moonbitlang/core/json"`, so the
  // alias is the last path segment. Without this rule every foreign reference
  // is unresolvable.
  let w = @map.World::build([
    pkg_of("app/main", ["moonbitlang/core/json", "mizchi/crater-core"], []),
  ])
  assert_eq(w.resolve_alias("app/main", "@json"), Some("moonbitlang/core/json"))
  // A hyphen survives: `mizchi/crater-core` is imported as `@crater-core`.
  assert_eq(
    w.resolve_alias("app/main", "@crater-core"),
    Some("mizchi/crater-core"),
  )
  assert_eq(w.resolve_alias("app/main", "@missing"), None)
}

///|
test "two imports with the same tail leave the alias unresolved" {
  // Guessing one of them would silently point annotations at the wrong
  // package, which is worse than degrading to `Any`.
  let w = @map.World::build([pkg_of("app/main", ["a/util", "b/util"], [])])
  assert_eq(w.resolve_alias("app/main", "@util"), None)
}

///|
test "the prelude alias always names the builtin package" {
  let w = @map.World::build([
    pkg_of("moonbitlang/core/builtin", [], [struct_of("Json", [])]),
  ])
  assert_eq(w.resolve_alias("app/main", "@builtin"), Some(@map.builtin_pkg))
}

///|
test "a method is indexed under the package that owns its receiver" {
  // `Json::stringify` is declared by the json package while `Json` lives in
  // builtin. Keying by the declaring package would attach it to nothing.
  let builtin = pkg_of("moonbitlang/core/builtin", [], [struct_of("Json", [])])
  let json = pkg_of("moonbitlang/core/json", [], [
    fn_of("stringify", Some({ pkg: None, name: "Json", }), plain("String")),
  ])
  let w = @map.World::build([builtin, json])
  let list = w.methods_on(@map.builtin_pkg, "Json").unwrap()
  assert_eq(list.length(), 1)
  assert_eq(list[0].0, "moonbitlang/core/json")
}

///|
test "a foreign type links to the other package's module" {
  let json = pkg_of("moonbitlang/core/json", [], [struct_of("Doc", [])])
  let app = pkg_of("app/main", ["moonbitlang/core/json"], [
    struct_of("Holder", [field_of("doc", qualified("@json", "Doc"))]),
  ])
  let w = @map.World::build([json, app])
  let m = @map.Mapper::for_world(w, "app/main", None).for_decl([], None)
  let ty = m.map(qualified("@json", "Doc"))
  // `_` plus the module stem: no generated class can collide with it.
  assert_eq(ty.render(), "_moonbitlang__core__json.Doc")
  assert_eq(m.imports(), ["moonbitlang__core__json"])
}

///|
test "a generic foreign type keeps its arguments" {
  let dep = pkg_of("acme/dep", [], [
    @mbti.Decl::Struct({
      name: "Box",
      generics: [{ name: "T", bounds: [], default: None, }],
      fields: [],
      has_hidden_fields: false,
      derives: [],
      attrs: [],
      access: @mbti.Open,
    }),
  ])
  let app = pkg_of("app/main", ["acme/dep"], [])
  let w = @map.World::build([dep, app])
  let m = @map.Mapper::for_world(w, "app/main", None).for_decl([], None)
  let ty = m.map(
    @mbti.TypeExpr::Named({ pkg: Some("@dep"), name: "Box", }, [plain("Int")]),
  )
  assert_eq(ty.render(), "_acme__dep.Box[int]")
}

///|
test "an arity mismatch on a linked type degrades instead of guessing" {
  let dep = pkg_of("acme/dep", [], [
    @mbti.Decl::Struct({
      name: "Box",
      generics: [{ name: "T", bounds: [], default: None, }],
      fields: [],
      has_hidden_fields: false,
      derives: [],
      attrs: [],
      access: @mbti.Open,
    }),
  ])
  let app = pkg_of("app/main", ["acme/dep"], [])
  let w = @map.World::build([dep, app])
  let m = @map.Mapper::for_world(w, "app/main", None).for_decl([], None)
  let ty = m.map(qualified("@dep", "Box"))
  assert_eq(ty.render(), "Any")
  assert_eq(m.count_reason("arity"), 1)
}

///|
test "an unqualified prelude type links through builtin" {
  // `.mbti` writes `Json`, not `@builtin.Json`, for anything in the implicit
  // prelude. With builtin in the world that name becomes a real reference.
  let builtin = pkg_of("moonbitlang/core/builtin", [], [
    @mbti.Decl::Enum({
      name: "Json",
      generics: [],
      ctors: [],
      derives: [],
      attrs: [],
      access: @mbti.Open,
    }),
  ])
  let app = pkg_of("app/main", [], [
    struct_of("Holder", [field_of("doc", plain("Json"))]),
  ])
  let w = @map.World::build([builtin, app])
  let m = @map.Mapper::for_world(w, "app/main", None).for_decl([], None)
  assert_eq(m.map(plain("Json")).render(), "_moonbitlang__core__builtin.Json")
}

///|
test "without a world the old behaviour is preserved" {
  // A single-package world knows nothing else, so a foreign reference still
  // degrades and the stub stays independently checkable.
  let app = pkg_of("app/main", ["moonbitlang/core/json"], [])
  let m = @map.Mapper::for_package(app).for_decl([], None)
  assert_eq(m.map(qualified("@json", "Doc")).render(), "Any")
  assert_eq(m.count_reason("foreign"), 1)
}

///|
test "rendering another package's local type qualifies it" {
  // When package B emits a method that package A declared, A's local names
  // must be written with A's module or B's stub would reference a class it
  // does not declare.
  let json = pkg_of("moonbitlang/core/json", [], [struct_of("Replacer", [])])
  let builtin = pkg_of("moonbitlang/core/builtin", [], [struct_of("Json", [])])
  let w = @map.World::build([json, builtin])
  let m = @map.Mapper::for_world(
    w,
    "moonbitlang/core/json",
    Some("moonbitlang/core/json"),
  ).for_decl([], None)
  assert_eq(
    m.map(plain("Replacer")).render(),
    "_moonbitlang__core__json.Replacer",
  )
}
