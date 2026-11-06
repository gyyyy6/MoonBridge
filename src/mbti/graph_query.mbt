//! Queries over a type graph: dependency order, cycles, external references.
//!
//! Code generation needs three answers in this order:
//!
//! 1. Which types must be emitted before this one? (`topo_order`)
//! 2. Which groups of types are mutually recursive and must be emitted
//!    together, with indirection? (`cycles` / `sccs`)
//! 3. Which referenced types do not live in this package at all?
//!    (`external_names`)

///|
/// Node names in sorted order, for deterministic reports.
fn sorted_node_names(
  graph : TypeGraph,
  indices : Array[Int32],
) -> Array[String] {
  let names = indices.map(fn(i) { graph.nodes[i].name })
  names.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  names
}

///|
/// Tallies nodes by kind.
pub fn TypeGraph::stats(self : TypeGraph) -> GraphStats {
  let mut s = 0
  let mut e = 0
  let mut err = 0
  let mut o = 0
  let mut a = 0
  let mut x = 0
  for n in self.nodes {
    match n.kind {
      Struct => s = s + 1
      Enum => e = e + 1
      Error => err = err + 1
      Opaque => o = o + 1
      Alias => a = a + 1
      External => x = x + 1
    }
  }
  {
    structs: s,
    enums: e,
    errors: err,
    opaques: o,
    aliases: a,
    externals: x,
    edges: self.edges.length(),
  }
}

///|
/// Indices of nodes declared in this package, sorted by name.
pub fn TypeGraph::local_indices(self : TypeGraph) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut i = 0
  while i < self.nodes.length() {
    if self.nodes[i].decl_index >= 0 {
      out.push(i)
    }
    i = i + 1
  }
  out
}

///|
/// Names referenced but not declared here, sorted. `Int`, `String` and friends
/// land here too: the generator resolves them against its builtin table.
pub fn TypeGraph::external_names(self : TypeGraph) -> Array[String] {
  let out : Array[Int32] = []
  let mut i = 0
  while i < self.nodes.length() {
    if self.nodes[i].decl_index < 0 {
      out.push(i)
    }
    i = i + 1
  }
  sorted_node_names(self, out)
}

///|
/// Names this type refers to, sorted and de-duplicated.
pub fn TypeGraph::deps_of(self : TypeGraph, name : String) -> Array[String] {
  let out : Array[Int32] = []
  match self.find(name) {
    Some(idx) =>
      for e in self.edges {
        if e.from == idx {
          out.push(e.to)
        }
      }
    None => ()
  }
  sorted_node_names(self, out)
}

///|
/// Builds the local-to-local adjacency used for ordering.
///
/// Three kinds of edge are ignored on purpose:
/// - edges into external types, which are never emitted here;
/// - `impl` edges, since implementing a trait does not require the trait's
///   declaring type to be emitted first;
/// - self edges, since a type may refer to itself (`enum Tree { Node(Tree) }`)
///   without needing to be emitted twice.
fn TypeGraph::ordering_edges(self : TypeGraph) -> Array[Array[Int32]] {
  let n = self.nodes.length()
  let adj : Array[Array[Int32]] = []
  let mut i = 0
  while i < n {
    adj.push([])
    i = i + 1
  }
  for e in self.edges {
    if e.kind == Impl || e.from == e.to {
      continue
    }
    if self.nodes[e.to].decl_index < 0 || self.nodes[e.from].decl_index < 0 {
      continue
    }
    // Edges point from a type to what it references; ordering needs the
    // opposite direction so dependencies are emitted first.
    adj[e.to].push(e.from)
  }
  adj
}

///|
/// Declaration order for the types of this package, or `None` when the package
/// contains mutually recursive types that cannot be ordered.
///
/// Ties are broken by name so the output is stable across runs.
pub fn TypeGraph::topo_order(self : TypeGraph) -> Array[String]? {
  let adj = self.ordering_edges()
  let n = self.nodes.length()
  let indegree : Array[Int32] = []
  let mut i = 0
  while i < n {
    indegree.push(0)
    i = i + 1
  }
  for from in 0..<n {
    for to in adj[from] {
      indegree[to] = indegree[to] + 1
    }
  }
  let emitted : Array[Bool] = []
  let mut i = 0
  while i < n {
    emitted.push(false)
    i = i + 1
  }
  let order : Array[Int32] = []
  while true {
    let mut pick = -1
    let mut j = 0
    while j < n {
      let is_local = self.nodes[j].decl_index >= 0
      if !emitted[j] && is_local && indegree[j] == 0 {
        if pick < 0 || self.nodes[j].name < self.nodes[pick].name {
          pick = j
        }
      }
      j = j + 1
    }
    if pick < 0 {
      break
    }
    emitted[pick] = true
    order.push(pick)
    for to in adj[pick] {
      indegree[to] = indegree[to] - 1
    }
  }
  let locals = self.local_indices()
  if order.length() != locals.length() {
    // Some local type never reached indegree zero: a cycle stopped the sweep.
    return None
  }
  Some(sorted_order_names(self, order))
}

///|
fn sorted_order_names(graph : TypeGraph, order : Array[Int32]) -> Array[String] {
  order.map(fn(i) { graph.nodes[i].name })
}

///|
/// Strongly connected components that contain a cycle, each sorted by name and
/// the whole list sorted by first member.
///
/// A component of one node means the type refers to itself; a larger component
/// means the types are mutually recursive.
pub fn TypeGraph::cycles(self : TypeGraph) -> Array[Array[String]] {
  let adj = self.ordering_edges()
  // Self edges were dropped for ordering; add them back for cycle detection.
  let self_ref : Array[Bool] = []
  let mut i = 0
  while i < self.nodes.length() {
    self_ref.push(false)
    i = i + 1
  }
  for e in self.edges {
    if e.from == e.to && e.kind != Impl {
      self_ref[e.from] = true
    }
  }
  let sccs = tarjan(adj)
  let out : Array[Array[String]] = []
  for comp in sccs {
    let mut is_cycle = comp.length() > 1
    if comp.length() == 1 && self_ref[comp[0]] {
      is_cycle = true
    }
    if is_cycle {
      out.push(sorted_node_names(self, comp))
    }
  }
  out.sort_by(fn(a, b) {
    if a[0] < b[0] {
      -1
    } else if a[0] > b[0] {
      1
    } else {
      0
    }
  })
  out
}

///|
/// Tarjan's SCC algorithm over the local subgraph.
///
/// Implemented with explicit state arrays and a recursive `strongconnect`,
/// which is fine for the hundreds of types a single package contains.
fn tarjan(adj : Array[Array[Int32]]) -> Array[Array[Int32]] {
  let n = adj.length()
  let index : Array[Int32] = []
  let low : Array[Int32] = []
  let on_stack : Array[Bool] = []
  let mut i = 0
  while i < n {
    index.push(-1)
    low.push(0)
    on_stack.push(false)
    i = i + 1
  }
  let stack : Array[Int32] = []
  let result : Array[Array[Int32]] = []
  // A one-element array is the box for the visit counter, so the recursive
  // helper can advance it without extra machinery.
  let counter : Array[Int32] = [0]
  for v in 0..<n {
    if index[v] < 0 {
      strongconnect(adj, v, index, low, on_stack, stack, result, counter)
    }
  }
  result
}

///|
fn strongconnect(
  adj : Array[Array[Int32]],
  v : Int32,
  index : Array[Int32],
  low : Array[Int32],
  on_stack : Array[Bool],
  stack : Array[Int32],
  result : Array[Array[Int32]],
  counter : Array[Int32],
) -> Unit {
  index[v] = counter[0]
  low[v] = counter[0]
  counter[0] = counter[0] + 1
  stack.push(v)
  on_stack[v] = true
  for w in adj[v] {
    if index[w] < 0 {
      strongconnect(adj, w, index, low, on_stack, stack, result, counter)
      if low[w] < low[v] {
        low[v] = low[w]
      }
    } else if on_stack[w] {
      if index[w] < low[v] {
        low[v] = index[w]
      }
    }
  }
  if low[v] == index[v] {
    let comp : Array[Int32] = []
    while true {
      let w = stack.pop().unwrap()
      on_stack[w] = false
      comp.push(w)
      if w == v {
        break
      }
    }
    result.push(comp)
  }
}
