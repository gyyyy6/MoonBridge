//! The callable module, asserted on the rendered text.
//!
//! A stub and a module come from the same walk, so the only thing worth
//! pinning here is the difference: the body that closes a signature. The rest
//! of the shape is already covered by `pyi_test.mbt`.

///|
fn has_bind(haystack : String, needle : String) -> Bool {
  if needle == "" {
    return true
  }
  haystack.split(needle).count() > 1
}

///|
/// One package of every kind that has, or has not, a symbol to call.
fn core_pkg() -> @mbti.Package {
  @mbti.parse_result(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) struct Point {\n" +
    "  x : Int\n" +
    "  mut y : Double\n" +
    "}\n" +
    "\n" +
    "pub(all) enum Shape {\n" +
    "  Circle(Double)\n" +
    "  Named(Point)\n" +
    "}\n" +
    "\n" +
    "pub fn Point::Point(x : Int, y : Double) -> Point\n" +
    "\n" +
    "pub fn Point::norm(Self) -> Double\n" +
    "\n" +
    "pub fn Shape::area(Self) -> Double\n" +
    "\n" +
    "pub fn report(s : Shape) -> Unit\n" +
    "\n" +
    "pub fn label(p : Point) -> String\n",
  ).unwrap()
}

///|
/// A module is generated against a plan: without one there are no symbols, so
/// nothing to call. Building the plan from the package itself is the smallest
/// honest fixture.
fn bind_of(src : String) -> @gen.Stub raise {
  let pkg = @mbti.parse(src)
  let world = @map.World::build([pkg])
  let plan = @gen.Plan::build(world, [pkg], [pkg.name])
  @gen.bind_with(Some(world), pkg, Some(plan), @gen.GenOptions::standard())
}

///|
test "the module announces itself and imports its own runtime" {
  let stub = bind_of("package \"acme/core\"\n\npub fn ping() -> Int\n")
  assert_true(
    has_bind(stub.text, "Bindings that call into the MoonBit package"),
  )
  // Deferred annotations are what let two generated modules import each other
  // without either of them being evaluated in the middle of the import.
  assert_true(has_bind(stub.text, "from __future__ import annotations"))
  assert_true(has_bind(stub.text, "from . import _runtime"))
  assert_false(has_bind(stub.text, "from moonbridge._runtime import"))
  assert_eq(stub.filename, "acme__core.py")
}

///|
test "a module function forwards to its own symbol" {
  let stub = bind_of(
    "package \"acme/core\"\n\npub fn label(p : Int) -> String\n",
  )
  assert_true(
    has_bind(
      stub.text,
      "def label(p: int, /) -> str:\n" +
      "    return cast(str, _runtime.default().request(\"acme/core::label\", [p]))",
    ),
  )
}

///|
test "a unit return does not return the payload" {
  // `-> None` with `return <Any>` is a strict-mode error, so the call and the
  // return have to be separated.
  let stub = bind_of(
    "package \"acme/core\"\n\npub fn report(text : String) -> Unit\n",
  )
  assert_true(
    has_bind(
      stub.text,
      "def report(text: str, /) -> None:\n" +
      "    _runtime.default().request(\"acme/core::report\", [text])\n" +
      "    return None",
    ),
  )
}

///|
test "a method passes its receiver and names the declaring package" {
  let stub = bind_of(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) struct Point {\n  x : Int\n}\n" +
    "\n" +
    "pub fn Point::norm(Self) -> Double\n",
  )
  assert_true(
    has_bind(
      stub.text,
      "    def norm(self, /) -> float:\n" +
      "        return cast(float, _runtime.default().request(\"acme/core::Point::norm\", [self]))",
    ),
  )
}

///|
test "an associated function is static and returns a wrapped handle" {
  let stub = bind_of(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) struct Point {\n  x : Int\n}\n" +
    "\n" +
    "pub fn Point::Point(x : Int) -> Point\n",
  )
  // `Point::Point` would shadow the class inside its own body, so it is `new`.
  assert_true(
    has_bind(stub.text, "    @staticmethod\n    def new(x: int, /) -> Point:"),
  )
  assert_true(
    has_bind(
      stub.text,
      "        return _runtime.wrap(Point, _runtime.default().request(\"acme/core::Point::Point\", [x]))",
    ),
  )
}

///|
test "a struct is constructed and read through the guest" {
  let stub = bind_of(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) struct Point {\n  x : Int\n  mut y : Double\n}\n" +
    "\n" +
    "pub(all) enum Shape {\n  Circle(Double)\n  Named(Point)\n}\n",
  )
  assert_true(has_bind(stub.text, "class Point(_runtime.MoonObject):"))
  // S4: the constructor makes the object in the guest and the wrapper takes
  // over the handle, so what Python holds *is* the MoonBit value rather than a
  // copy that could drift from it.
  assert_true(
    has_bind(
      stub.text,
      "def __init__(self, x: int, y: float) -> None:\n" +
      "        super().__init__(cast(int, _runtime.default().request(\"acme/core::Point::__new__\", [x, y])), _runtime.default())",
    ),
  )
  // Reads and writes go through generated getter and setter symbols; a field
  // that is not `mut` gets no setter, because the guest has nothing to call.
  assert_true(
    has_bind(
      stub.text,
      "    @property\n" +
      "    def x(self) -> int:\n" +
      "        return cast(int, _runtime.default().request(\"acme/core::Point::__get_x\", [self]))",
    ),
  )
  assert_true(
    has_bind(stub.text, "    @y.setter\n    def y(self, value: float) -> None:"),
  )
  assert_false(has_bind(stub.text, "@x.setter"))
  // An enum is not constructible from Python: its payload shapes have no single
  // signature, and the guest has no symbol that would pick one.
  assert_false(
    has_bind(
      stub.text,
      "class Shape(_runtime.MoonObject):\n    \"\"\"MoonBit enum `Shape`.\n    def __init__",
    ),
  )
  assert_false(has_bind(stub.text, "def tag"))
}

///|
test "a cross-package handle is wrapped in the class its own module defines" {
  let ext = @mbti.parse_result(
    "package \"acme/ext\"\n" +
    "\n" +
    "import {\n  \"acme/base\",\n}\n" +
    "\n" +
    "pub fn make(n : Int) -> @base.Gadget\n",
  ).unwrap()
  let base = @mbti.parse_result(
    "package \"acme/base\"\n\npub(all) struct Gadget {\n  size : Int\n}\n",
  ).unwrap()
  let world = @map.World::build([base, ext])
  // Both packages are compiled into the guest, so `Gadget` crosses by handle
  // and the ext module can wrap it in the base module's class.
  let plan = @gen.Plan::build(world, [base, ext], ["acme/base", "acme/ext"])
  let stub = @gen.bind_with(
    Some(world),
    ext,
    Some(plan),
    @gen.GenOptions::standard(),
  )
  // The sibling is imported at the top for the type checker and again inside
  // the body for the interpreter, which is what keeps two modules that
  // reference each other importable.
  assert_true(
    has_bind(
      stub.text,
      "if TYPE_CHECKING:\n    from . import acme__base as _acme__base",
    ),
  )
  assert_true(
    has_bind(
      stub.text,
      "def make(n: int, /) -> _acme__base.Gadget:\n" +
      "    from . import acme__base as _acme__base\n" +
      "    return _runtime.wrap(_acme__base.Gadget, _runtime.default().request(\"acme/ext::make\", [n]))",
    ),
  )
}

///|
test "a trait protocol keeps an ellipsis body in both outputs" {
  // A Protocol has no guest object to dispatch to; `...` is the body Python
  // expects, so the module must not try to call one.
  let src = "package \"acme/core\"\n" +
    "\n" +
    "pub(open) trait Show {\n  to_string(Self) -> String\n}\n"
  let stub = bind_of(src)
  assert_true(has_bind(stub.text, "    def to_string(self, /) -> str: ..."))
  assert_false(has_bind(stub.text, "acme/core::Show::to_string"))
}

///|
/// A package where one type crosses as a handle and another cannot, so the tag
/// emitter can be checked in both directions.
fn tagged_pkg_and_plan() -> (@mbti.Package, @map.World, @gen.Plan) {
  let pkg = @mbti.parse_result(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) enum Shape {\n" +
    "  Circle(Double)\n" +
    "  Named(Point)\n" +
    "}\n" +
    "\n" +
    "pub(all) struct Point {\n" +
    "  x : Int\n" +
    "}\n" +
    "\n" +
    "pub struct Sealed {\n" +
    "  value : Int\n" +
    "}\n" +
    "\n" +
    "pub fn draw(s : Shape) -> Shape\n",
  ).unwrap()
  let world = @map.World::build([pkg])
  let plan = @gen.Plan::build(world, [pkg], ["acme/core"])
  (pkg, world, plan)
}

///|
fn bind_of_tagged() -> (@gen.Stub, @gen.Plan) {
  let (pkg, world, plan) = tagged_pkg_and_plan()
  (
    @gen.bind_with(Some(world), pkg, Some(plan), @gen.GenOptions::standard()),
    plan,
  )
}

///|
test "a class that stands for a handle carries its table tag" {
  // `Json` is an enum and `parse` hands back a handle to one, so a class that
  // reads like a value still needs a tag: without one `close()` queues an id
  // the guest cannot route to a table, and the object outlives its wrapper for
  // the life of the process. This is the leak the S4 smoke test found.
  let (stub, plan) = bind_of_tagged()
  let tag = plan.tag_of("@core.Shape")
  assert_true(tag > 0)
  assert_true(has_bind(stub.text, "    moon_type_id = " + tag.to_string()))
}

///|
test "a class the guest never holds keeps no tag" {
  // `Sealed` is a `pub struct`: its fields are hidden, so no constructor, no
  // getter and no table. Emitting a tag would promise a routing the guest does
  // not have, and `close()` would then lose the id silently.
  let (stub, plan) = bind_of_tagged()
  assert_eq(plan.tag_of("@core.Sealed"), 0)
  assert_true(has_bind(stub.text, "class Sealed(_runtime.MoonObject):"))
  // Exactly one tag in the module, and it is the enum's: `Shape` and `Point`
  // are the only tables the plan asked for, and `Point` is declared here while
  // its tag is emitted where the class is.
  assert_eq(stub.text.split("moon_type_id").count(), 3)
}

///|
test "the module and the stub agree on every callable name" {
  let pkg = core_pkg()
  let world = @map.World::build([pkg])
  let plan = @gen.Plan::build(world, [pkg], [pkg.name])
  let stub = @gen.generate(pkg, @gen.GenOptions::standard())
  let bind = @gen.bind_with(
    Some(world),
    pkg,
    Some(plan),
    @gen.GenOptions::standard(),
  )
  // Same walk, same names: whatever the stub promises, the module can answer.
  for
    name in ["def label(", "def norm(", "def area(", "def report(", "def new("] {
    assert_true(has_bind(stub.text, name))
    assert_true(has_bind(bind.text, name))
  }
}
