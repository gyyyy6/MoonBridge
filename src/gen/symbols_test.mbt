//! What the planner decides, asserted without rendering anything.
//!
//! These tests pin the part that both halves of a binding depend on: which
//! declarations become symbols, what they are called, how their values cross,
//! and which concrete types end up with a handle table. A mistake here is a
//! mistake on both sides at once, which is exactly why it is worth pinning.

///|
/// The implicit prelude: owns `Widget`, declares one method on it.
fn wire_prelude() -> @mbti.Package {
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
/// A package that declares methods on `Widget` and owns a struct of its own.
fn wire_json() -> @mbti.Package {
  @mbti.parse_result(
    "package \"acme/json\"\n" +
    "\n" +
    "import {\n" +
    "  \"moonbitlang/core/builtin\",\n" +
    "}\n" +
    "\n" +
    "pub(all) suberror ParseError {\n" +
    "  Bad\n" +
    "}\n" +
    "\n" +
    "pub fn parse(String, depth? : Int) -> Widget raise ParseError\n" +
    "\n" +
    "pub fn Widget::label(Self, sep? : String) -> String\n" +
    "\n" +
    "pub(all) struct Node {\n" +
    "  name : String\n" +
    "  mut weight : Double\n" +
    "}\n" +
    "\n" +
    "pub fn takes_array(Array[Int]) -> Unit\n" +
    "\n" +
    "pub fn takes_closure((Int) -> Int) -> Int\n" +
    "\n" +
    "pub fn takes_map(Map[String, Int]) -> Int\n" +
    "\n" +
    "pub fn takes_result(String) -> Result[Int, ParseError]\n" +
    "\n" +
    "pub fn takes_tuple((Int, Int)) -> Unit\n" +
    "\n" +
    "pub fn takes_view_map(Map[String, StringView]) -> Unit\n" +
    "\n" +
    "pub fn labeled(x~ : Int) -> Int\n",
  ).unwrap()
}

///|
/// A package the guest is not compiled for: its types cannot be held.
fn wire_outside() -> @mbti.Package {
  @mbti.parse_result(
    "package \"acme/outside\"\n" +
    "\n" +
    "pub(all) struct Token {\n" +
    "  text : String\n" +
    "}\n",
  ).unwrap()
}

///|
fn plan_of(guest : Array[String]) -> @gen.Plan {
  let world = @map.World::build([wire_prelude(), wire_json(), wire_outside()])
  @gen.Plan::build(world, [wire_prelude(), wire_json(), wire_outside()], guest)
}

///|
fn standard_plan() -> @gen.Plan {
  plan_of(["moonbitlang/core/builtin", "acme/json"])
}

///|
test "a free function keeps its package-qualified symbol" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::parse").unwrap()
  assert_eq(sym.kind, @gen.Free)
  assert_eq(sym.decl_pkg, "acme/json")
  // The string is the whole contract: the Python module sends it, the guest's
  // dispatch matches on it.
  assert_eq(sym.symbol, "acme/json::parse")
  assert_true(sym.raises)
}

///|
test "an optional parameter travels as a maybe" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::parse").unwrap()
  // `parse(String, depth? : Int)` — the callee sees `Int?`, and Python sends
  // `None` when the caller omitted it.
  assert_eq(sym.params.length(), 2)
  assert_eq(sym.params[0], @gen.WStr)
  assert_eq(sym.params[1], WMaybe(@gen.WInt))
  // The result is a handle, not a value: a parsed document stays in the guest.
  assert_eq(
    sym.ret,
    WHandle({
      expr: "@builtin.Widget",
      pkg: "moonbitlang/core/builtin",
      key: "builtin_Widget",
    }),
  )
}

///|
test "a method declared away from its type still takes the receiver" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::Widget::label").unwrap()
  assert_eq(sym.kind, @gen.Method)
  assert_eq(sym.owner, "Widget")
  // `Self` resolves to the receiver's home package, not the declaring one.
  assert_eq(
    sym.params[0],
    WHandle({
      expr: "@builtin.Widget",
      pkg: "moonbitlang/core/builtin",
      key: "builtin_Widget",
    }),
  )
  assert_eq(sym.params[1], WMaybe(@gen.WStr))
  assert_eq(sym.ret, @gen.WStr)
}

///|
test "a struct yields a constructor, a getter per field and a setter per mut field" {
  let plan = standard_plan()
  let ctor = plan.lookup("acme/json::Node::__new__").unwrap()
  assert_eq(ctor.kind, @gen.Ctor)
  assert_eq(ctor.params, [@gen.WStr, @gen.WDouble])
  assert_eq(
    ctor.ret,
    WHandle({ expr: "@json.Node", pkg: "acme/json", key: "json_Node", }),
  )

  let name = plan.lookup("acme/json::Node::__get_name").unwrap()
  assert_eq(name.kind, @gen.Getter)
  assert_eq(name.params, [
    WHandle({ expr: "@json.Node", pkg: "acme/json", key: "json_Node", }),
  ])
  assert_eq(name.ret, @gen.WStr)

  // `weight` is `mut`, so it gets a setter as well as a getter.
  assert_true(plan.has("acme/json::Node::__get_weight"))
  let setter = plan.lookup("acme/json::Node::__set_weight").unwrap()
  assert_eq(setter.kind, @gen.Setter)
  assert_eq(setter.params, [
    WHandle({ expr: "@json.Node", pkg: "acme/json", key: "json_Node", }),
    @gen.WDouble,
  ])
  assert_eq(setter.ret, @gen.WUnit)
}

///|
test "every concrete type that crosses gets its own table, numbered from one" {
  let plan = standard_plan()
  // Two types appear: `Widget` (from builtin) and `Node` (from json).
  assert_eq(plan.handles.length(), 2)
  assert_eq(plan.tag_of("@builtin.Widget"), 1)
  assert_eq(plan.tag_of("@json.Node"), 2)
  // Zero keeps meaning "no object" on the Python side.
  assert_eq(plan.tag_of("@acme.Token"), 0)
}

///|
test "a value the frame cannot carry is skipped with a counted reason" {
  let plan = standard_plan()
  // S5 closed the container gap: a list, a map and a callable all travel now.
  assert_true(plan.has("acme/json::takes_array"))
  assert_true(plan.has("acme/json::takes_map"))
  assert_true(plan.has("acme/json::takes_closure"))
  assert_true(plan.has("acme/json::takes_result"))
  // A tuple has no shape, and a borrowed view cannot outlive a container.
  assert_false(plan.has("acme/json::takes_tuple"))
  assert_false(plan.has("acme/json::takes_view_map"))
  assert_false(plan.has("acme/json::labeled"))
  let mut params = 0
  let mut labeled = 0
  for entry in plan.skipped {
    match entry {
      ("unmarshalable-param", n) => params = n
      ("labeled-param", n) => labeled = n
      _ => ()
    }
  }
  // The tuple, and the map whose values are borrowed views.
  assert_eq(params, 2)
  assert_eq(labeled, 1)
}

///|
test "an array parameter is a list on the wire" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::takes_array").unwrap()
  // Python's `list[int]` — no wrapper, no tag: the shape is the element shape.
  assert_eq(sym.params, [WArr(@gen.WInt)])
}

///|
test "a map parameter keeps both of its sides" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::takes_map").unwrap()
  // Python's `dict[str, int]`; a `Map` is a container like any other, so it can
  // nest inside one.
  assert_eq(sym.params, [WMap(@gen.WStr, @gen.WInt)])
}

///|
test "a callable parameter becomes a callback shape" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::takes_closure").unwrap()
  // `(Int) -> Int` crosses as an id plus the signature the host has to honour.
  assert_eq(sym.params, [WCall([@gen.WInt], @gen.WInt)])
}

///|
test "a result return names the error the Python caller will catch" {
  let plan = standard_plan()
  let sym = plan.lookup("acme/json::takes_result").unwrap()
  // `Ok` carries the value, and the error side is only a message: Python has no
  // value to hand over for `Err`, it has a `raise`.
  assert_eq(sym.ret, WRes(@gen.WInt, @gen.WStr))
  // Even though the declaration says no `raise`, the `Result` names the error
  // type, and that name is what the generated exception class is called.
  assert_eq(sym.error_type, "acme/json::ParseError")
}

///|
test "a receiver from a package the guest does not compile is skipped" {
  // `acme/outside` is only generated as a stub, so a handle to its type has no
  // table to live in and a method on it has nowhere to go.
  let plan = plan_of(["acme/json"])
  assert_false(plan.has("acme/json::parse"))
  let reasons : Array[String] = []
  for entry in plan.skipped {
    match entry {
      (reason, _) => reasons.push(reason)
    }
  }
  // The return type is the first thing that fails: `Widget` is not in the
  // guest, so there is no table to hold the result.
  assert_true(reasons.contains("unmarshalable-return"))
}

///|
test "skip reasons are sorted, so two runs report the same thing" {
  let plan = standard_plan()
  let mut previous = ""
  for entry in plan.skipped {
    match entry {
      (reason, count) => {
        assert_true(count > 0)
        assert_true(previous <= reason)
        previous = reason
      }
    }
  }
}

///|
test "a type key is an identifier, even for a hyphenated alias" {
  assert_eq(@gen.wire_key("@json.Position"), "json_Position")
  assert_eq(@gen.wire_key("@crater-core.Frame"), "crater_core_Frame")
}
