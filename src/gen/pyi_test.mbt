//! Stub generation, asserted on the rendered text.
//!
//! These tests are the contract for S2: the shape of every declaration kind is
//! pinned here, so a change in the emitter shows up as a failing string
//! comparison rather than as a surprise in a downstream `mypy` run.

///|
fn contains(haystack : String, needle : String) -> Bool {
  if needle == "" {
    return true
  }
  haystack.split(needle).count() > 1
}

///|
fn sample() -> String {
  "package \"demo/demo\"\n" +
  "\n" +
  "import {\n" +
  "  \"moonbitlang/core/json\",\n" +
  "}\n" +
  "\n" +
  "pub(all) struct Point {\n" +
  "  x : Int\n" +
  "  y : Double\n" +
  "  mut label : String\n" +
  "}\n" +
  "\n" +
  "pub struct Document {\n" +
  "  // private fields\n" +
  "}\n" +
  "\n" +
  "pub typealias Coord = (Int, Double)\n" +
  "\n" +
  "pub(all) enum Shape {\n" +
  "  Circle(Double)\n" +
  "  Named(Point)\n" +
  "}\n" +
  "\n" +
  "pub suberror ParseError {\n" +
  "  ParseError(String)\n" +
  "}\n" +
  "\n" +
  "pub(open) trait Show {\n" +
  "  to_string(Self) -> String\n" +
  "}\n" +
  "\n" +
  "pub(all) struct Box[T] {\n" +
  "  value : T\n" +
  "}\n" +
  "\n" +
  "pub fn area(shape : Shape) -> Double\n" +
  "\n" +
  "pub fn Point::norm(Self) -> Double\n" +
  "\n" +
  "pub fn Point::scaled(Self, k? : Double, axis~ : String) -> Point\n" +
  "\n" +
  "pub fn[T] identity(x : T) -> T\n" +
  "\n" +
  "pub fn load(path : String) -> @json.Json\n" +
  "\n" +
  "pub fn find(text : String) -> Point?\n" +
  "\n" +
  "pub let origin : Point\n" +
  "\n" +
  "pub const MAX_DIM : Int = 1024\n"
}

///|
fn stub_of(src : String) -> @gen.Stub raise {
  let pkg = @mbti.parse(src)
  @gen.generate(pkg, @gen.GenOptions::standard())
}

///|
test "header names the source package" {
  let stub = stub_of(sample())
  assert_true(
    contains(stub.text, "Type stubs for the MoonBit package `demo/demo`."),
  )
  assert_eq(stub.filename, "demo__demo.pyi")
}

///|
test "struct becomes a handle class with a typed constructor" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class Point(MoonObject):"))
  assert_true(
    contains(
      stub.text,
      "    def __init__(self, x: int, y: float, label: str) -> None: ...",
    ),
  )
  assert_true(contains(stub.text, "    def x(self) -> int: ..."))
  assert_true(contains(stub.text, "    def y(self) -> float: ..."))
}

///|
test "mutable fields get a setter" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "    @label.setter"))
  assert_true(
    contains(stub.text, "    def label(self, value: str) -> None: ..."),
  )
}

///|
test "hidden fields suppress the constructor" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class Document(MoonObject):"))
  // A struct whose fields are private cannot be built from Python, so the stub
  // must not advertise an `__init__` that would accept nothing.
  assert_false(
    contains(
      stub.text,
      "class Document(MoonObject):\n    \"\"\"MoonBit struct `Document`.\"\"\"\n    def __init__",
    ),
  )
}

///|
test "multi-constructor enum exposes a tag" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class Shape(MoonObject):"))
  assert_true(
    contains(
      stub.text,
      "    def __init__(self, tag: str, *args: Any) -> None: ...",
    ),
  )
  assert_true(contains(stub.text, "    def tag(self) -> str: ..."))
}

///|
test "suberror extends MoonError and names its message" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class ParseError(MoonError):"))
  assert_true(
    contains(stub.text, "    def __init__(self, message: str) -> None: ..."),
  )
  // The error base, not the handle base, is what an error extends.
  assert_false(contains(stub.text, "class ParseError(MoonObject):"))
}

///|
test "trait becomes a protocol with the receiver dropped" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class Show(Protocol):"))
  // `.mbti` prints the receiver as a leading `Self`; the stub turns it into
  // Python's `self` instead of emitting a second parameter.
  assert_true(contains(stub.text, "    def to_string(self, /) -> str: ..."))
}

///|
test "method receiver becomes self" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "    def norm(self, /) -> float: ..."))
}

///|
test "optional and labeled parameters become keyword-only" {
  let stub = stub_of(sample())
  assert_true(
    contains(
      stub.text,
      "    def scaled(self, /, *, k: Optional[float] = ..., axis: str) -> Point: ...",
    ),
  )
}

///|
test "generic struct parameterises the class" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "class Box(MoonObject, Generic[T]):"))
  assert_true(contains(stub.text, "    def value(self) -> T: ..."))
  assert_true(contains(stub.text, "T = TypeVar(\"T\")"))
}

///|
test "generic function keeps its type variable" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "def identity(x: T, /) -> T: ..."))
}

///|
test "alias is a TypeAlias of the mapped target" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "Coord: TypeAlias = tuple[int, float]"))
}

///|
test "module functions are positional-only" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "def area(shape: Shape, /) -> float: ..."))
}

///|
test "optional return type is Optional" {
  let stub = stub_of(sample())
  assert_true(
    contains(stub.text, "def find(text: str, /) -> Optional[Point]: ..."),
  )
}

///|
test "foreign return type degrades to Any and is reported" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "def load(path: str, /) -> Any: ..."))
  let mut foreign = 0
  for d in stub.degraded {
    match d {
      @map.ForeignType(_) => foreign = foreign + 1
      _ => ()
    }
  }
  assert_eq(foreign, 1)
}

///|
test "values and constants are annotated" {
  let stub = stub_of(sample())
  assert_true(contains(stub.text, "origin: Point"))
  assert_true(contains(stub.text, "MAX_DIM: int"))
}

///|
test "imports only mention what the stub uses" {
  let stub = stub_of(sample())
  // `Protocol` and `Generic` are used, `Sequence` and `MoonError` are not part
  // of this sample, and the runtime import lists exactly one base class.
  assert_true(
    contains(
      stub.text,
      "from typing import Any, Generic, Optional, Protocol, TypeAlias, TypeVar",
    ),
  )
  assert_false(contains(stub.text, "Sequence"))
  assert_true(
    contains(stub.text, "from moonbridge._runtime import MoonError, MoonObject"),
  )
}

///|
test "counters describe what was emitted" {
  let stub = stub_of(sample())
  // Point, Document, Shape, ParseError, Show, Box, plus the Coord alias.
  assert_eq(stub.types, 7)
  // area, identity, load, find, origin, MAX_DIM.
  assert_eq(stub.funcs, 6)
  // x, y, label on Point, value on Box.
  assert_eq(stub.fields, 4)
  assert_eq(stub.skipped, 0)
}

///|
test "an empty package still produces a valid stub" {
  let stub = stub_of("package \"demo/empty\"\n")
  assert_true(contains(stub.text, "package `demo/empty`"))
  assert_true(contains(stub.text, "Do not edit by hand."))
  assert_false(contains(stub.text, "from typing"))
}
