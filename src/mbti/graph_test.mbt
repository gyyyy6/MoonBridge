//! Black-box tests for type-graph construction and its queries.

///|
fn graph_of(src : String) -> @mbti.TypeGraph raise @mbti.ParseError {
  @mbti.TypeGraph::build(@mbti.parse(src))
}

///|
fn wrap(body : String) -> String {
  "package \"demo\"\n\n" + body + "\n"
}

///|
test "graph: struct fields become edges and drive ordering" {
  let g = graph_of(
    wrap("pub(all) struct A {\n  b : B\n}\n\npub(all) struct B {\n  n : Int\n}"),
  )
  assert_eq(g.node_count(), 3) // A, B, Int
  assert_eq(g.deps_of("A"), ["B"])
  assert_eq(g.deps_of("B"), ["Int"])
  // B must be emitable before A because A embeds a B by value.
  assert_eq(g.topo_order(), Some(["B", "A"]))
  assert_eq(g.cycles(), [])
}

///|
test "graph: generic parameters are not types" {
  let g = graph_of(wrap("pub fn[T] wrap(x : T) -> Array[T]"))
  // `T` is bound by the declaration, so it must not become a node.
  assert_eq(g.external_names(), ["Array"])
  assert_eq(g.node_count(), 1)
}

///|
test "graph: method signatures attach to their receiver" {
  let g = graph_of(
    wrap(
      "pub(all) struct Buffer {\n  data : Bytes\n}\n\npub fn Buffer::push(Self, Byte) -> Unit",
    ),
  )
  assert_eq(g.deps_of("Buffer"), ["Byte", "Bytes"])
  // `Self` resolves to Buffer itself, not to a node called Self.
  match g.find("Self") {
    Some(_) => fail("Self must not become a node")
    None => ()
  }
}

///|
test "graph: self-referential types stay orderable but are reported" {
  let g = graph_of(wrap("pub(all) enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}"))
  // A type may mention itself without needing to be emitted twice.
  assert_eq(g.topo_order(), Some(["Tree"]))
  assert_eq(g.cycles(), [["Tree"]])
}

///|
test "graph: mutually recursive types cannot be ordered" {
  let g = graph_of(
    wrap("pub(all) struct A {\n  b : B\n}\n\npub(all) struct B {\n  a : A\n}"),
  )
  assert_eq(g.topo_order(), None)
  assert_eq(g.cycles(), [["A", "B"]])
}

///|
test "graph: impl edges do not constrain declaration order" {
  let g = graph_of(
    wrap("pub(all) struct Point {\n  x : Int\n}\n\npub impl Show for Point"),
  )
  assert_eq(g.topo_order(), Some(["Point"]))
  // The trait is referenced but not declared here.
  assert_eq(g.external_names(), ["Int", "Show"])
}

///|
test "graph: qualified and alias types" {
  let g = graph_of(
    wrap(
      "pub type Fd = Int\n\npub(all) struct Row {\n  payload : @builtin.Json\n}",
    ),
  )
  assert_eq(g.stats().aliases, 1)
  assert_eq(g.stats().structs, 1)
  assert_eq(g.stats().externals, 2)
  assert_eq(g.deps_of("Fd"), ["Int"])
  assert_eq(g.deps_of("Row"), ["@builtin.Json"])
}

///|
test "graph: arity is recorded for generic declarations" {
  let g = graph_of(
    wrap("pub(all) struct Pair[A, B] {\n  first : A\n  second : B\n}"),
  )
  match g.find("Pair") {
    Some(i) => assert_eq(g.nodes[i].arity, 2)
    None => fail("Pair must be a node")
  }
  // Neither A nor B is a real dependency.
  assert_eq(g.deps_of("Pair"), [])
}

///|
test "graph: externals and locals are separated" {
  let g = graph_of(wrap("pub(all) struct Box {\n  v : Thing\n}\n\ntype Opaque"))
  assert_eq(g.local_indices().length(), 2)
  assert_eq(g.external_names(), ["Thing"])
  assert_eq(g.stats().opaques, 1)
}
