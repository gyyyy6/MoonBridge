//! Cross-package generation, asserted on the rendered text.
//!
//! Two behaviours are pinned here: a foreign type becomes a module-qualified
//! reference (never a bare name), and a method declared in one package lands on
//! the class emitted by the package that owns the receiver.

///|
fn has(haystack : String, needle : String) -> Bool {
  if needle == "" {
    return true
  }
  haystack.split(needle).count() > 1
}

///|
/// Stands in for the implicit prelude: it declares `Widget` and one method on
/// it, the way `moonbitlang/core/builtin` declares `Json`.
fn prelude_pkg() -> @mbti.Package {
  @mbti.parse_result(
    "package \"moonbitlang/core/builtin\"\n" +
    "\n" +
    "pub(all) struct Widget {\n" +
    "  id : Int\n" +
    "}\n" +
    "\n" +
    "pub fn Widget::ident(Self) -> Int\n",
  ).unwrap()
}

///|
/// A plain dependency with no relation to the prelude.
fn base_pkg() -> @mbti.Package {
  @mbti.parse_result(
    "package \"acme/base\"\n" +
    "\n" +
    "pub(all) struct Gadget {\n" +
    "  size : Int\n" +
    "}\n",
  ).unwrap()
}

///|
/// Declares a method on a type it does not own, and mentions a type it imports.
fn ext_pkg() -> @mbti.Package {
  @mbti.parse_result(
    "package \"acme/ext\"\n" +
    "\n" +
    "import {\n" +
    "  \"acme/base\",\n" +
    "}\n" +
    "\n" +
    "pub fn Widget::touch(Self, force? : Bool) -> Unit\n" +
    "\n" +
    "pub fn wrap(g : @base.Gadget) -> @base.Gadget\n",
  ).unwrap()
}

///|
fn world_of() -> @map.World {
  @map.World::build([prelude_pkg(), base_pkg(), ext_pkg()])
}

///|
test "a foreign type is referenced through its module, and imported" {
  let stub = @gen.generate_with(
    Some(world_of()),
    ext_pkg(),
    @gen.GenOptions::standard(),
  )
  // A bare `Gadget` here would resolve to nothing in this module.
  assert_true(
    has(
      stub.text,
      "def wrap(g: _acme__base.Gadget, /) -> _acme__base.Gadget: ...",
    ),
  )
  assert_true(has(stub.text, "from . import acme__base as _acme__base"))
  assert_eq(stub.imports, ["acme__base"])
  // A linked reference is a typed reference, so nothing degraded.
  assert_eq(stub.degraded.length(), 0)
}

///|
test "a method declared elsewhere lands on the class that owns the type" {
  // `acme/ext` declares `Widget::touch` while `Widget` is emitted by the
  // prelude package. Without the world index the method has nowhere to live
  // and is dropped, which is what S2 did.
  let stub = @gen.generate_with(
    Some(world_of()),
    prelude_pkg(),
    @gen.GenOptions::standard(),
  )
  assert_true(
    has(
      stub.text,
      "    def touch(self, /, *, force: Optional[bool] = ...) -> None: ...",
    ),
  )
  assert_true(has(stub.text, "class Widget(MoonObject):"))
}

///|
test "the receiver's package still names its own types bare" {
  let stub = @gen.generate_with(
    Some(world_of()),
    prelude_pkg(),
    @gen.GenOptions::standard(),
  )
  assert_true(has(stub.text, "    def ident(self, /) -> int: ..."))
  // A module never imports itself, even when it owns a type with foreign
  // methods attached.
  assert_false(has(stub.text, "from . import moonbitlang__core__builtin"))
}

///|
test "a stub that links nothing still compiles alone" {
  let pkg = @mbti.parse_result(
    "package \"acme/solo\"\n\npub fn ping() -> Int\n",
  ).unwrap()
  let stub = @gen.generate(pkg, @gen.GenOptions::standard())
  assert_false(has(stub.text, "from . import"))
  assert_eq(stub.imports.length(), 0)
}

///|
test "an alias to a package outside the world stays Any" {
  // `acme/ext` imports `acme/base`, but this run only includes `acme/ext`.
  let stub = @gen.generate(ext_pkg(), @gen.GenOptions::standard())
  assert_true(has(stub.text, "def wrap(g: Any, /) -> Any: ..."))
  assert_false(has(stub.text, "from . import"))
  // One per position: the parameter and the return type.
  assert_eq(stub.degraded.length(), 2)
}
