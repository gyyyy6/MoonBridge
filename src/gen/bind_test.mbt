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
fn bind_of(src : String) -> @gen.Stub raise {
  let pkg = @mbti.parse(src)
  @gen.bind_with(None, pkg, @gen.GenOptions::standard())
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
test "fields and constructors are declared but not bound" {
  let stub = bind_of(
    "package \"acme/core\"\n" +
    "\n" +
    "pub(all) struct Point {\n  x : Int\n  mut y : Double\n}\n" +
    "\n" +
    "pub(all) enum Shape {\n  Circle(Double)\n  Named(Point)\n}\n",
  )
  assert_true(has_bind(stub.text, "class Point(_runtime.MoonObject):"))
  // No guest symbol reads a field or runs a constructor yet, and a body that
  // raised would only move the failure from generation time to call time.
  assert_false(has_bind(stub.text, "def __init__"))
  assert_false(has_bind(stub.text, "@property"))
  assert_false(has_bind(stub.text, "def tag"))
}

///|
test "a cross-package handle is wrapped in the class its own module defines" {
  let world = @map.World::build([
    @mbti.parse_result(
      "package \"acme/base\"\n\npub(all) struct Gadget {\n  size : Int\n}\n",
    ).unwrap(),
    @mbti.parse_result(
      "package \"acme/ext\"\n" +
      "\n" +
      "import {\n  \"acme/base\",\n}\n" +
      "\n" +
      "pub fn make(n : Int) -> @base.Gadget\n",
    ).unwrap(),
  ])
  let stub = @gen.bind_with(
    Some(world),
    @mbti.parse_result(
      "package \"acme/ext\"\n" +
      "\n" +
      "import {\n  \"acme/base\",\n}\n" +
      "\n" +
      "pub fn make(n : Int) -> @base.Gadget\n",
    ).unwrap(),
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
test "the module and the stub agree on every callable name" {
  let stub = @gen.generate(core_pkg(), @gen.GenOptions::standard())
  let bind = @gen.bind_with(None, core_pkg(), @gen.GenOptions::standard())
  // Same walk, same names: whatever the stub promises, the module can answer.
  for
    name in ["def label(", "def norm(", "def area(", "def report(", "def new("] {
    assert_true(has_bind(stub.text, name))
    assert_true(has_bind(bind.text, name))
  }
}
