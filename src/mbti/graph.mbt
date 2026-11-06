//! Type graph construction.
//!
//! The parser produces a flat list of declarations; a binding generator cannot
//! use that directly. It needs to know which types exist, which depend on
//! which, and in what order they can be emitted. This module turns a `Package`
//! into a directed graph where nodes are types and edges are references.
//!
//! Two properties matter for code generation and are first-class here:
//!
//! - **Generics are scoped.** `fn[T] f(T) -> Array[T]` mentions `T`, which is a
//!   type *variable*, not a type. Bound names are filtered per declaration, so
//!   the graph never contains phantom nodes called `T`.
//! - **External types stay in the graph.** `@builtin.Json` is a node with
//!   `decl_index = -1`; the generator maps those to host-language types instead
//!   of trying to emit them.

///|
/// What a graph node stands for.
pub(all) enum TypeKind {
  Struct
  Enum
  /// `suberror`.
  Error
  /// An opaque `type X` declaration.
  Opaque
  /// `typealias` / `type X = Y`.
  Alias
  /// Referenced but not declared in this package.
  External
} derive(Debug, Eq)

///|
/// A type node. `decl_index` indexes into `Package.decls` and is `-1` for
/// external types.
pub(all) struct TypeNode {
  /// Local name for declarations, qualified text (`@builtin.Json`) for
  /// external references.
  name : String
  kind : TypeKind
  /// Number of generic parameters the declaration takes.
  arity : Int32
  decl_index : Int32
  /// `Some("@builtin")` for qualified external references.
  pkg : String?
} derive(Debug, Eq)

///|
/// Why an edge exists.
pub(all) enum EdgeKind {
  /// Struct field type or constructor payload.
  Field
  /// Parameter, return type or declared error type.
  Signature
  /// `impl Trait for Type`.
  Impl
  /// Alias target.
  Alias
} derive(Debug, Eq)

///|
/// Short stable tag, used in de-duplication keys and in reports.
pub fn EdgeKind::tag(self : EdgeKind) -> String {
  match self {
    Field => "field"
    Signature => "sig"
    Impl => "impl"
    Alias => "alias"
  }
}

///|
pub(all) struct Edge {
  from : Int32
  to : Int32
  kind : EdgeKind
} derive(Debug, Eq)

///|
/// Counts useful for reports and for the CLI summary line.
pub(all) struct GraphStats {
  structs : Int32
  enums : Int32
  errors : Int32
  opaques : Int32
  aliases : Int32
  externals : Int32
  edges : Int32
} derive(Debug, Eq)

///|
/// The type graph of a single package.
pub(all) struct TypeGraph {
  nodes : Array[TypeNode]
  edges : Array[Edge]
} derive(Debug, Eq)

///|
pub fn TypeGraph::node_count(self : TypeGraph) -> Int32 {
  self.nodes.length()
}

///|
pub fn TypeGraph::edge_count(self : TypeGraph) -> Int32 {
  self.edges.length()
}

///|
/// Looks a node up by the exact name used in the graph.
pub fn TypeGraph::find(self : TypeGraph, name : String) -> Int32? {
  let mut i = 0
  while i < self.nodes.length() {
    if self.nodes[i].name == name {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Accumulates nodes and edges while walking declarations.
///
/// Kept separate from `TypeGraph` so the two passes stay obvious: pass one
/// registers every declared type, pass two resolves references against that
/// registry.
priv struct Builder {
  /// Node index of the type that owns the declaration being walked, or `-1`.
  mut owner : Int32
  /// Names bound by the enclosing declaration's `[T, U]` header.
  mut bound : Array[String]
  nodes : Array[TypeNode]
  edges : Array[Edge]
  /// `from|to|kind` keys of edges already added.
  seen : Map[String, Bool]
}

///|
fn Builder::new() -> Builder {
  { owner: -1, bound: [], nodes: [], edges: [], seen: Map([]), }
}

///|
fn Builder::index_of(self : Builder, name : String) -> Int32? {
  let mut i = 0
  while i < self.nodes.length() {
    if self.nodes[i].name == name {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn Builder::is_bound(self : Builder, name : String) -> Bool {
  self.bound.contains(name)
}

///|
/// Resolves a reference to a node index, creating an external node the first
/// time a name is seen.
fn Builder::resolve(self : Builder, name : String, pkg : String?) -> Int32 {
  let key = match pkg {
    Some(p) => p + "." + name
    None => name
  }
  match self.index_of(key) {
    Some(i) => i
    None => {
      self.nodes.push({
        name: key,
        kind: External,
        arity: 0,
        decl_index: -1,
        pkg,
      })
      self.nodes.length() - 1
    }
  }
}

///|
fn Builder::add_edge(
  self : Builder,
  from : Int32,
  to : Int32,
  kind : EdgeKind,
) -> Unit {
  if from < 0 || to < 0 {
    return
  }
  let key = from.to_string() + "|" + to.to_string() + "|" + kind.tag()
  if self.seen.contains(key) {
    return
  }
  self.seen.set(key, true)
  self.edges.push({ from, to, kind, })
}

///|
/// Records every name mentioned by `ty`, skipping generic parameters and
/// resolving `Self` to the enclosing type.
fn Builder::walk(self : Builder, ty : TypeExpr, kind : EdgeKind) -> Unit {
  let names : Array[QName] = []
  ty.collect_names(names)
  for q in names {
    if self.is_bound(q.name) {
      continue
    }
    let target = if q.pkg is None && q.name == "Self" {
      self.owner
    } else {
      let key = match q.pkg {
        Some(p) => p + "." + q.name
        None => q.name
      }
      match self.index_of(key) {
        Some(i) => i
        None => self.resolve(q.name, q.pkg)
      }
    }
    self.add_edge(self.owner, target, kind)
  }
}

///|
fn Builder::walk_signature(self : Builder, f : FuncDecl) -> Unit {
  for p in f.params {
    self.walk(p.ty, Signature)
  }
  self.walk(f.ret, Signature)
  match f.effect.error {
    Some(e) => self.walk(e, Signature)
    None => ()
  }
}

///|
fn Builder::register_declared(
  self : Builder,
  decl : Decl,
  index : Int32,
) -> Unit {
  let node = match decl {
    Struct(s) =>
      Some({
        name: s.name,
        kind: Struct,
        arity: s.generics.length(),
        decl_index: index,
        pkg: None,
      })
    Enum(e) =>
      Some({
        name: e.name,
        kind: Enum,
        arity: e.generics.length(),
        decl_index: index,
        pkg: None,
      })
    Error(e) =>
      Some({
        name: e.name,
        kind: Error,
        arity: e.generics.length(),
        decl_index: index,
        pkg: None,
      })
    Opaque(o) =>
      Some({
        name: o.name,
        kind: Opaque,
        arity: o.generics.length(),
        decl_index: index,
        pkg: None,
      })
    Alias(a) =>
      Some({
        name: a.name,
        kind: Alias,
        arity: a.generics.length(),
        decl_index: index,
        pkg: None,
      })
    _ => None
  }
  match node {
    Some(n) => self.nodes.push(n)
    None => ()
  }
}

///|
/// Binds `[T, U]` so references to them are not mistaken for types.
fn Builder::bind_generics(
  self : Builder,
  generics : Array[GenericParam],
) -> Unit {
  self.bound = generics.map(fn(g) { g.name })
}

///|
fn Builder::walk_decl(self : Builder, decl : Decl) -> Unit {
  self.owner = -1
  self.bound = []
  match decl {
    Struct(s) => {
      self.owner = match self.index_of(s.name) {
        Some(i) => i
        None => -1
      }
      self.bind_generics(s.generics)
      for f in s.fields {
        self.walk(f.ty, Field)
      }
    }
    Enum(e) => {
      self.owner = match self.index_of(e.name) {
        Some(i) => i
        None => -1
      }
      self.bind_generics(e.generics)
      for c in e.ctors {
        for f in c.fields {
          self.walk(f.ty, Field)
        }
      }
    }
    Error(e) => {
      self.owner = match self.index_of(e.name) {
        Some(i) => i
        None => -1
      }
      self.bind_generics(e.generics)
      for c in e.ctors {
        for f in c.fields {
          self.walk(f.ty, Field)
        }
      }
    }
    Opaque(o) => {
      self.owner = match self.index_of(o.name) {
        Some(i) => i
        None => -1
      }
      self.bind_generics(o.generics)
    }
    Alias(a) => {
      self.owner = match self.index_of(a.name) {
        Some(i) => i
        None => -1
      }
      self.bind_generics(a.generics)
      self.walk(a.target, Alias)
    }
    Trait(t) => {
      // `Self` in a trait method means "the implementing type", which is not a
      // node, so these signatures contribute no edges.
      self.bind_generics(t.generics)
      let saved = self.owner
      self.owner = -1
      for m in t.methods {
        self.walk_signature(m)
      }
      self.owner = saved
    }
    Func(f) => {
      self.bind_generics(f.generics)
      match f.receiver {
        Some(r) => {
          let key = match r.pkg {
            Some(p) => p + "." + r.name
            None => r.name
          }
          self.owner = match self.index_of(key) {
            Some(i) => i
            None => -1
          }
        }
        None => self.owner = -1
      }
      self.walk_signature(f)
    }
    Value(v) => {
      self.owner = -1
      self.walk(v.ty, Signature)
    }
    Const(c) => {
      self.owner = -1
      self.walk(c.ty, Signature)
    }
    Impl(i) => {
      let names : Array[QName] = []
      i.for_ty.collect_names(names)
      self.owner = -1
      match names {
        [first, ..] => {
          let key = match first.pkg {
            Some(p) => p + "." + first.name
            None => first.name
          }
          let from = match self.index_of(key) {
            Some(idx) => idx
            None => self.resolve(first.name, first.pkg)
          }
          let trait_node = self.resolve(i.trait_name.name, i.trait_name.pkg)
          self.add_edge(from, trait_node, Impl)
        }
        [] => ()
      }
    }
    Reexport(_) => ()
  }
}

///|
/// Builds the graph for a parsed package.
pub fn TypeGraph::build(pkg : Package) -> TypeGraph {
  let b = Builder::new()
  // Pass 1: every declared type becomes a node, so later references resolve
  // locally instead of turning into externals.
  let mut i = 0
  while i < pkg.decls.length() {
    b.register_declared(pkg.decls[i], i)
    i = i + 1
  }
  // Pass 2: resolve references.
  i = 0
  while i < pkg.decls.length() {
    b.walk_decl(pkg.decls[i])
    i = i + 1
  }
  { nodes: b.nodes, edges: b.edges, }
}
