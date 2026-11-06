//! Behaviour of the MoonBit -> Python type table.
//!
//! Each test pins one rung of the mapping ladder: exact counterparts, the
//! transparent erasures, the handle form, and the degradations. The
//! degradation tests assert both the resulting `Any` *and* the recorded reason,
//! because a silent `Any` is the failure mode this module exists to prevent.

///|
fn named(name : String) -> @mbti.TypeExpr {
  @mbti.TypeExpr::Named(@mbti.QName::plain(name), [])
}

///|
fn generic(name : String, args : Array[@mbti.TypeExpr]) -> @mbti.TypeExpr {
  @mbti.TypeExpr::Named(@mbti.QName::plain(name), args)
}

///|
fn int_ty() -> @mbti.TypeExpr {
  named("Int")
}

///|
test "primitives map exactly" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(int_ty()).render(), "int")
  assert_eq(m.map(named("Double")).render(), "float")
  assert_eq(m.map(named("Bool")).render(), "bool")
  assert_eq(m.map(named("String")).render(), "str")
  assert_eq(m.map(named("StringView")).render(), "str")
  assert_eq(m.map(named("Bytes")).render(), "bytes")
  assert_eq(m.map(named("Unit")).render(), "None")
  assert_eq(@map.PyType::render(m.map(@mbti.TypeExpr::Unit)), "None")
  assert_eq(m.degraded_count(), 0)
}

///|
test "integer widths all collapse to int" {
  let m = @map.Mapper::new("demo")
  for width in ["Int8", "Int16", "Int32", "Int64", "UInt", "UInt64", "BigInt"] {
    assert_eq(m.map(named(width)).render(), "int")
  }
  assert_eq(m.degraded_count(), 0)
}

///|
test "containers compose" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(generic("Array", [int_ty()])).render(), "list[int]")
  assert_eq(m.map(generic("FixedArray", [int_ty()])).render(), "list[int]")
  // A view is read-only, so `Sequence` rather than `list`.
  assert_eq(m.map(generic("ArrayView", [int_ty()])).render(), "Sequence[int]")
  assert_eq(
    m
    .map(generic("Map", [named("String"), generic("Array", [int_ty()])]))
    .render(),
    "dict[str, list[int]]",
  )
  assert_eq(m.degraded_count(), 0)
}

///|
test "optional is a single layer" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(@mbti.TypeExpr::Optional(int_ty())).render(), "Optional[int]")
  let doubled = @mbti.TypeExpr::Optional(@mbti.TypeExpr::Optional(int_ty()))
  assert_eq(m.map(doubled).render(), "Optional[int]")
  // `Option[T]` spelled as a named type behaves the same as `T?`.
  assert_eq(m.map(generic("Option", [int_ty()])).render(), "Optional[int]")
  assert_eq(m.degraded_count(), 0)
}

///|
test "tuples" {
  let m = @map.Mapper::new("demo")
  assert_eq(
    m.map(@mbti.TypeExpr::Tuple([int_ty(), named("String")])).render(),
    "tuple[int, str]",
  )
  assert_eq(m.map(@mbti.TypeExpr::Tuple([])).render(), "tuple[()]")
}

///|
test "borrow is transparent" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(@mbti.TypeExpr::Borrowed(int_ty())).render(), "int")
  assert_eq(m.degraded_count(), 0)
}

///|
test "result keeps the value and notes the loss" {
  let m = @map.Mapper::new("demo")
  let t = m.map(generic("Result", [int_ty(), named("String")]))
  assert_eq(t.render(), "int")
  assert_eq(m.count_reason("result"), 1)
}

///|
test "function values degrade" {
  let m = @map.Mapper::new("demo")
  let f = @mbti.TypeExpr::Func(
    [{ kind: @mbti.Positional, name: None, ty: int_ty(), }],
    named("Bool"),
    @mbti.Effect::pure(),
  )
  assert_eq(m.map(f).render(), "Any")
  assert_eq(m.count_reason("higher-order"), 1)
}

///|
test "async values degrade" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(@mbti.TypeExpr::Async(int_ty())).render(), "Any")
  assert_eq(m.count_reason("async"), 1)
}

///|
test "foreign types degrade to any" {
  let m = @map.Mapper::new("demo")
  let foreign = @mbti.TypeExpr::Named(@mbti.QName::qualified("@json", "Json"), [])
  assert_eq(m.map(foreign).render(), "Any")
  assert_eq(m.count_reason("foreign"), 1)
}

///|
test "unknown names degrade to any" {
  let m = @map.Mapper::new("demo")
  assert_eq(m.map(named("Mystery")).render(), "Any")
  assert_eq(m.count_reason("unknown"), 1)
}

///|
test "local types become handles" {
  let m = @map.Mapper::new("demo")
  m.register("Json", 0)
  m.register("Box", 1)
  assert_eq(m.map(named("Json")).render(), "Json")
  assert_eq(m.map(generic("Box", [int_ty()])).render(), "Box[int]")
  assert_eq(m.degraded_count(), 0)
}

///|
test "arity mismatch degrades" {
  let m = @map.Mapper::new("demo")
  m.register("Box", 1)
  // `Box` takes one argument; written bare it is not the same type.
  assert_eq(m.map(named("Box")).render(), "Any")
  assert_eq(m.count_reason("arity"), 1)
  assert_eq(m.map(generic("Box", [int_ty(), int_ty()])).render(), "Any")
  assert_eq(m.count_reason("arity"), 2)
}

///|
test "type variables render by name" {
  let m = @map.Mapper::new("demo")
  let scoped = m.for_decl([{ name: "T", bounds: [], default: None, }], None)
  assert_eq(scoped.map(named("T")).render(), "T")
  assert_eq(scoped.map(generic("Array", [named("T")])).render(), "list[T]")
  assert_eq(scoped.degraded_count(), 0)
}

///|
test "type variables do not leak out of scope" {
  let m = @map.Mapper::new("demo")
  // Without the generic in scope, `T` is just an unknown name.
  assert_eq(m.map(named("T")).render(), "Any")
  assert_eq(m.count_reason("unknown"), 1)
}

///|
test "self resolves inside a type" {
  let m = @map.Mapper::new("demo")
  let inside = m.for_decl([], Some("Json"))
  assert_eq(inside.map(@mbti.TypeExpr::SelfType([])).render(), "Json")
  assert_eq(inside.degraded_count(), 0)
  // No receiver, no `Self`.
  assert_eq(m.map(@mbti.TypeExpr::SelfType([])).render(), "Any")
  assert_eq(m.count_reason("unbound-self"), 1)
}

///|
test "deep nesting is cut off" {
  let m = @map.Mapper::new("demo")
  let mut deep = int_ty()
  for _ in 0..<40 {
    deep = @mbti.TypeExpr::Optional(deep)
  }
  assert_eq(m.map(deep).render(), "Any")
  assert_eq(m.count_reason("too-deep"), 1)
}

///|
test "for package registers declared types" {
  let pkg = @mbti.Package::{
    name: "demo/demo",
    imports: [],
    decls: [
      @mbti.Struct({
        name: "Point",
        generics: [],
        fields: [],
        has_hidden_fields: false,
        derives: [],
        attrs: [],
        access: @mbti.Open,
      }),
      @mbti.Enum({
        name: "Box",
        generics: [{ name: "T", bounds: [], default: None, }],
        ctors: [],
        derives: [],
        attrs: [],
        access: @mbti.Open,
      }),
      @mbti.Reexport({
        pkg: "@json",
        entries: [{ kind: "type", name: "Json", as_name: None, }],
      }),
    ],
  }
  let m = @map.Mapper::for_package(pkg)
  assert_eq(m.map(named("Point")).render(), "Point")
  assert_eq(m.map(generic("Box", [int_ty()])).render(), "Box[int]")
  // A re-exported type has unknown arity: bare use is fine, instantiation is not.
  assert_eq(m.map(named("Json")).render(), "Json")
  assert_eq(m.map(generic("Json", [int_ty()])).render(), "Any")
  assert_eq(m.count_reason("arity"), 1)
}

///|
test "qualified builtin is still builtin" {
  let m = @map.Mapper::new("demo")
  let q = @mbti.TypeExpr::Named(@mbti.QName::qualified("@builtin", "Int"), [])
  assert_eq(m.map(q).render(), "int")
  assert_eq(m.degraded_count(), 0)
}

///|
test "render types joins with comma space" {
  assert_eq(@map.render_types([@map.PyInt, @map.PyStr]), "int, str")
  assert_eq(@map.render_types([]), "")
}

///|
test "degrades are described" {
  assert_eq(
    @map.Degrade::describe(@map.ForeignType("@json.Json")),
    "foreign type @json.Json -> Any",
  )
  assert_eq(
    @map.Degrade::describe(@map.HigherOrderFunction),
    "function value -> Any (callbacks are not bridged)",
  )
}
