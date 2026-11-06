//! From interface declarations to the symbols a guest can answer.
//!
//! A binding has two halves — the Python module and the MoonBit guest — and the
//! only thing that keeps them from disagreeing is that both are derived from
//! this one plan. S3 hand-wrote the guest's dispatch next to a generated Python
//! module, which works exactly until someone edits one side. Here the guest's
//! branches, its handle tables and the Python bodies are all read off the same
//! list of symbols.
//!
//! The planner decides three things per declaration:
//!
//! 1. **Can this value cross at all?** `Wire` names the shapes the frame can
//!    carry. Anything else — a closure, an array, a generic — is skipped with a
//!    counted reason rather than guessed at, because a wrong guess fails at the
//!    call site instead of at generation time.
//! 2. **What does the caller say?** Each symbol is a string that both halves
//!    spell identically: `<declaring package>::<Type>::<name>`, or
//!    `<declaring package>::<function>` for a free function.
//! 3. **Which concrete types need a handle table?** Only the ones that actually
//!    appear on the wire, numbered so a release can be routed to its table.

///|
/// A concrete type that is addressed by a handle.
pub(all) struct TyRef {
  /// The MoonBit type expression, e.g. `@json.Position`.
  expr : String
  /// An identifier-safe spelling, e.g. `json_Position`. Used for the table, its
  /// helpers and the Python class attribute.
  key : String
} derive(Debug, Eq)

///|
/// How one value crosses the boundary.
///
/// Deliberately small. Each variant is one conversion in the guest's decoder and
/// one in the Python codec; adding one is a decision about the ABI, not a
/// convenience for the generator.
pub(all) enum Wire {
  /// `Int` — 32-bit, fixed width.
  WInt
  /// `Double` — IEEE 754, fixed width.
  WDouble
  WBool
  WStr
  /// `StringView`: a string on the wire, a view in the guest.
  WStrView
  /// `Unit`: nothing on the wire.
  WUnit
  /// `T?`. In a return position `None` is `null`; in a parameter position it
  /// means the callee declared the parameter optional.
  WMaybe(Wire)
  /// A value that stays in the guest's heap.
  WHandle(TyRef)
} derive(Debug, Eq)

///|
/// What a symbol does, which decides how the guest writes the call.
pub(all) enum SymKind {
  /// A package-level function: `@pkg.name(args)`.
  Free
  /// A method, associated function or constructor function on a type:
  /// `@pkg.Type::name(args)`.
  Method
  /// A struct literal: `@pkg.Type::{ field: value, ... }`.
  Ctor
  /// A field read: `value.field`.
  Getter
  /// A field write: copy, assign, write back.
  Setter
} derive(Debug, Eq)

///|
pub fn SymKind::label(self : SymKind) -> String {
  match self {
    Free => "free"
    Method => "method"
    Ctor => "ctor"
    Getter => "get"
    Setter => "set"
  }
}

///|
/// One callable the guest can answer, and everything needed to write both
/// halves from it.
pub(all) struct Sym {
  kind : SymKind
  /// The string on the wire, and the only thing the two halves share at
  /// runtime.
  symbol : String
  /// The package that declared it. Not necessarily the receiver's package:
  /// `Json::stringify` is declared by `json` and attached to `builtin`'s `Json`.
  decl_pkg : String
  /// Raw MoonBit type name of the receiver, empty for a free function.
  owner : String
  /// Raw name of the function or field.
  name : String
  /// Parameter shapes, receiver first when the symbol takes one.
  params : Array[Wire]
  ret : Wire
  raises : Bool
} derive(Debug)

///|
/// A concrete type that needs its own handle table.
///
/// One table per type because MoonBit has no runtime type information: a single
/// table would have to store a boxed union, and there is no boxed union. The tag
/// is what lets a release batch name which table an id belongs to.
pub(all) struct HandleSlot {
  ty : TyRef
  /// The number the Python wrapper sends back when releasing. Starts at 1 so
  /// that 0 keeps meaning "no object".
  tag : Int32
} derive(Debug)

///|
/// Everything the guest generator and the Python generator need to agree on.
pub(all) struct Plan {
  /// Packages whose guest code is compiled in, in the order requested.
  guest : Array[String]
  syms : Array[Sym]
  handles : Array[HandleSlot]
  /// Why declarations were left out, by reason, sorted by reason.
  skipped : Array[(String, Int32)]
}

///|
pub fn Plan::empty() -> Plan {
  { guest: [], syms: [], handles: [], skipped: [], }
}

///|
/// The symbol for a struct constructor.
pub fn ctor_symbol(pkg : String, owner : String) -> String {
  pkg + "::" + owner + "::__new__"
}

///|
/// The symbol for a field read.
pub fn getter_symbol(pkg : String, owner : String, field : String) -> String {
  pkg + "::" + owner + "::__get_" + field
}

///|
/// The symbol for a field write.
pub fn setter_symbol(pkg : String, owner : String, field : String) -> String {
  pkg + "::" + owner + "::__set_" + field
}

///|
pub fn Plan::lookup(self : Plan, symbol : String) -> Sym? {
  let mut found : Sym? = None
  let mut i = 0
  while i < self.syms.length() {
    if self.syms[i].symbol == symbol {
      found = Some(self.syms[i])
    }
    i = i + 1
  }
  found
}

///|
/// Whether a symbol is in the plan. The Python emitter asks this before writing
/// a body, so a member either has a call behind it or is not written at all.
pub fn Plan::has(self : Plan, symbol : String) -> Bool {
  match self.lookup(symbol) {
    Some(_) => true
    None => false
  }
}

///|
/// The tag of the table that holds `ty`, or 0 when the type never crosses.
pub fn Plan::tag_of(self : Plan, ty : String) -> Int32 {
  let mut tag = 0
  let mut i = 0
  while i < self.handles.length() {
    if self.handles[i].ty.expr == ty {
      tag = self.handles[i].tag
    }
    i = i + 1
  }
  tag
}

///|
pub fn Plan::count(self : Plan, kind : SymKind) -> Int32 {
  let mut n = 0
  for s in self.syms {
    if s.kind == kind {
      n = n + 1
    }
  }
  n
}

///|
pub fn Plan::summary(self : Plan) -> String {
  let parts : Array[String] = []
  for kind in [Free, Method, Ctor, Getter, Setter] {
    let n = self.count(kind)
    if n > 0 {
      parts.push(kind.label() + "=" + n.to_string())
    }
  }
  "symbols=" +
  self.syms.length().to_string() +
  " (" +
  join_strings(parts, " ") +
  ") tables=" +
  self.handles.length().to_string()
}

///|
fn join_strings(items : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < items.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(items[i])
    i = i + 1
  }
  sb.to_string()
}

///|
/// Turns a package alias into something that can lead a MoonBit identifier:
/// `@crater-core` becomes `crater_core`. The alias already had its `@` removed
/// by the caller.
fn alias_key(at : String) -> String {
  let sb = StringBuilder()
  for ch in at {
    if ch == '-' {
      sb.write_char('_')
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// An identifier-safe name for a handle type: `@json.Position` becomes
/// `json_Position`.
pub fn wire_key(ty : String) -> String {
  let parts = ty.split(".").to_array()
  let sb = StringBuilder()
  let mut i = 0
  while i < parts.length() {
    let part = parts[i]
    if i > 0 {
      sb.write_string("_")
    }
    // The first segment is always `@alias`; the `@` is punctuation, not a name.
    let text = if i == 0 && part.length() > 0 {
      part.exact_view(start=1).to_owned()
    } else if i == 0 {
      ""
    } else {
      part.to_owned()
    }
    sb.write_string(alias_key(text))
    i = i + 1
  }
  sb.to_string()
}

///|
fn has_attr(attrs : Array[@mbti.Attr], name : String) -> Bool {
  let mut found = false
  for a in attrs {
    if a.name == name {
      found = true
    }
  }
  found
}

///|
/// Accumulates a plan while walking declarations.
priv struct Builder {
  world : @map.World
  guest : Array[String]
  syms : Array[Sym]
  handles : Array[HandleSlot]
  skipped : Map[String, Int32]
  /// Next table tag. Kept as a counter rather than derived from the table
  /// count so that a tag is never reused after a type is added twice.
  mut next_tag : Int32
}

///|
fn Builder::skip(self : Builder, reason : String) -> Unit {
  self.skipped.set(reason, self.skipped.get(reason).unwrap_or(0) + 1)
}

///|
/// The MoonBit type expression for `q`, when `q` names a concrete type whose
/// package is compiled into this guest. `None` means "this value cannot be
/// addressed by a handle", which is the honest answer for a generic, an
/// unknown name, or a type from a package the guest does not compile.
fn Builder::resolve_handle(
  self : Builder,
  pkg : String,
  q : @mbti.QName,
) -> TyRef? {
  let home = match self.world.home_of(pkg, q) {
    Some(h) => h
    None => return None
  }
  if !self.guest.contains(home) {
    return None
  }
  // Only an arity-0 type can be named without arguments; a generic
  // instantiation would need its arguments marshalled too.
  match self.world.arity_of(home, q.name) {
    Some(0) => {
      let at = @map.pkg_alias(home)
      Some({ expr: at + "." + q.name, key: wire_key(at + "." + q.name), })
    }
    _ => None
  }
}

///|
/// The wire shape of a value coming in, or `None` when it cannot be decoded.
fn Builder::wire_in(
  self : Builder,
  pkg : String,
  ty : @mbti.TypeExpr,
  owner : TyRef?,
) -> Wire? {
  match ty {
    @mbti.Unit => Some(WUnit)
    @mbti.Named(q, args) =>
      if args.length() > 0 {
        None
      } else {
        match q.name {
          "Int" => Some(WInt)
          "Double" => Some(WDouble)
          "Bool" => Some(WBool)
          "String" => Some(WStr)
          "StringView" => Some(WStrView)
          "Unit" => Some(WUnit)
          _ =>
            match self.resolve_handle(pkg, q) {
              Some(t) => Some(WHandle(t))
              None => None
            }
        }
      }
    @mbti.SelfType(args) =>
      if args.length() > 0 {
        None
      } else {
        match owner {
          Some(o) => Some(WHandle(o))
          None => None
        }
      }
    _ => None
  }
}

///|
/// The wire shape of a value going out. Same rules plus `Option`, which a
/// return position can express and the input side never needs.
fn Builder::wire_out(
  self : Builder,
  pkg : String,
  ty : @mbti.TypeExpr,
  owner : TyRef?,
) -> Wire? {
  match ty {
    @mbti.Optional(inner) =>
      match self.wire_out(pkg, inner, owner) {
        // `T??` is not a shape the frame has; refusing keeps the decoder total.
        Some(WMaybe(_)) => None
        Some(w) => Some(WMaybe(w))
        None => None
      }
    _ => self.wire_in(pkg, ty, owner)
  }
}

///|
fn Builder::add(self : Builder, sym : Sym) -> Unit {
  // The same symbol can be reached from two packages — `Json::stringify` is
  // declared by `json` and attached to `builtin`'s `Json` — and the guest can
  // only answer it once.
  let mut seen = false
  let mut i = 0
  while i < self.syms.length() {
    if self.syms[i].symbol == sym.symbol {
      seen = true
    }
    i = i + 1
  }
  if !seen {
    self.syms.push(sym)
  }
}

///|
/// A method or free function.
fn Builder::func_decl(self : Builder, pkg : String, f : @mbti.FuncDecl) -> Unit {
  if f.access == @mbti.Private {
    return self.skip("private")
  }
  if f.is_async {
    return self.skip("async")
  }
  if f.generics.length() > 0 {
    return self.skip("generic")
  }
  if has_attr(f.attrs, "deprecated") {
    return self.skip("deprecated")
  }
  let mut owner : TyRef? = None
  let mut owner_raw = ""
  let mut rest = f.params
  match f.receiver {
    Some(r) => {
      let slot = match self.resolve_handle(pkg, r) {
        Some(t) => t
        None =>
          // The receiver's own package is not compiled into this guest, or the
          // receiver is generic: either way there is no table to hold it.
          return self.skip("receiver-not-in-guest")
      }
      owner_raw = r.name
      owner = Some(slot)
      if f.params.length() > 0 && is_self_ty(f.params[0].ty) {
        // The receiver is passed as argument zero, because that is what the
        // Python side sends: `self` followed by the declared parameters.
        rest = drop_receiver(f.params)
      }
    }
    None => ()
  }
  let params : Array[Wire] = []
  match owner {
    Some(o) => params.push(WHandle(o))
    None => ()
  }
  for p in rest {
    match p.kind {
      @mbti.Labeled =>
        // A `~label` parameter cannot be passed positionally, and inventing an
        // order for it would put the argument in the wrong slot.
        return self.skip("labeled-param")
      _ => ()
    }
    let w = match self.wire_in(pkg, p.ty, owner) {
      Some(w) => w
      None => return self.skip("unmarshalable-param")
    }
    // An `x? : T` parameter arrives as `T?` in the callee, and Python sends
    // `None` when the caller left it out, so the two shapes agree exactly.
    params.push(
      match p.kind {
        @mbti.Optional => WMaybe(w)
        _ => w
      },
    )
  }
  let ret = match self.wire_out(pkg, f.ret, owner) {
    Some(r) => r
    None => return self.skip("unmarshalable-return")
  }
  let kind = if owner_raw == "" { Free } else { Method }
  let symbol = if owner_raw == "" {
    pkg + "::" + f.name
  } else {
    pkg + "::" + owner_raw + "::" + f.name
  }
  self.add({
    kind,
    symbol,
    decl_pkg: pkg,
    owner: owner_raw,
    name: f.name,
    params,
    ret,
    raises: f.effect.raises,
  })
}

///|
/// A struct: one constructor, one getter per visible field, one setter per
/// mutable one.
fn Builder::struct_decl(
  self : Builder,
  pkg : String,
  s : @mbti.StructDecl,
) -> Unit {
  if s.access != @mbti.Open {
    // `pub struct` hides its fields, so there is nothing to construct from and
    // nothing to read. It is still a perfectly good handle type.
    return self.skip("hidden-struct")
  }
  if s.generics.length() > 0 {
    return self.skip("generic-struct")
  }
  if s.has_hidden_fields {
    return self.skip("hidden-fields")
  }
  if s.fields.length() == 0 {
    return self.skip("empty-struct")
  }
  let at = @map.pkg_alias(pkg)
  let owner : TyRef = {
    expr: at + "." + s.name,
    key: wire_key(at + "." + s.name),
  }
  let visible : Array[@mbti.Field] = []
  for f in s.fields {
    if f.access != @mbti.Private {
      visible.push(f)
    }
  }
  // A positional field has no MoonBit name, so a literal cannot be written.
  let mut named = true
  for f in visible {
    if f.name == "" {
      named = false
    }
  }
  if !named {
    return self.skip("unnamed-field")
  }
  let ctor_params : Array[Wire] = []
  let mut ctor_ok = true
  for f in visible {
    match self.wire_in(pkg, f.ty, Some(owner)) {
      Some(w) => ctor_params.push(w)
      None => ctor_ok = false
    }
  }
  if ctor_ok {
    self.add({
      kind: Ctor,
      symbol: ctor_symbol(pkg, s.name),
      decl_pkg: pkg,
      owner: s.name,
      name: "__new__",
      params: ctor_params,
      ret: WHandle(owner),
      raises: false,
    })
  } else {
    self.skip("unmarshalable-field")
  }
  for f in visible {
    match self.wire_out(pkg, f.ty, Some(owner)) {
      Some(w) =>
        self.add({
          kind: Getter,
          symbol: getter_symbol(pkg, s.name, f.name),
          decl_pkg: pkg,
          owner: s.name,
          name: f.name,
          params: [WHandle(owner)],
          ret: w,
          raises: false,
        })
      None => self.skip("unreadable-field")
    }
    if f.is_mut {
      match self.wire_in(pkg, f.ty, Some(owner)) {
        Some(w) =>
          self.add({
            kind: Setter,
            symbol: setter_symbol(pkg, s.name, f.name),
            decl_pkg: pkg,
            owner: s.name,
            name: f.name,
            params: [WHandle(owner), w],
            ret: WUnit,
            raises: false,
          })
        None => self.skip("unwritable-field")
      }
    }
  }
}

///|
fn Builder::note_handle(self : Builder, w : Wire) -> Unit {
  match w {
    WHandle(slot) => {
      let mut seen = false
      let mut i = 0
      while i < self.handles.length() {
        if self.handles[i].ty.expr == slot.expr {
          seen = true
        }
        i = i + 1
      }
      if !seen {
        self.handles.push({ ty: slot, tag: self.next_tag, })
        self.next_tag = self.next_tag + 1
      }
    }
    WMaybe(inner) => self.note_handle(inner)
    _ => ()
  }
}

///|
/// Sorts the skip reasons so two runs of the generator print the same report.
fn sorted_reasons(skipped : Map[String, Int32]) -> Array[(String, Int32)] {
  let keys : Array[String] = []
  for k in skipped.keys() {
    keys.push(k)
  }
  let mut i = 1
  while i < keys.length() {
    let key = keys[i]
    let mut j = i
    while j > 0 && keys[j - 1] > key {
      keys[j] = keys[j - 1]
      j = j - 1
    }
    keys[j] = key
    i = i + 1
  }
  let out : Array[(String, Int32)] = []
  for k in keys {
    out.push((k, skipped.get(k).unwrap_or(0)))
  }
  out
}

///|
/// Builds the plan for `guest` from the parsed corpus.
pub fn Plan::build(
  world : @map.World,
  packages : Array[@mbti.Package],
  guest : Array[String],
) -> Plan {
  let b : Builder = {
    world,
    guest,
    syms: [],
    handles: [],
    skipped: Map([]),
    next_tag: 1,
  }
  for path in guest {
    let mut found : @mbti.Package? = None
    for p in packages {
      if p.name == path {
        found = Some(p)
      }
    }
    match found {
      Some(p) =>
        for decl in p.decls {
          match decl {
            @mbti.Decl::Func(f) => b.func_decl(path, f)
            @mbti.Struct(s) => b.struct_decl(path, s)
            // Enums, traits, aliases and constants are part of the type surface
            // the stub describes, but none of them is callable, so they are not
            // counted as skipped bindings.
            _ => ()
          }
        }
      None => b.skip("no-interface")
    }
  }
  // Number the tables in order of first appearance, which keeps the numbers
  // stable across runs and makes the generated guest diffable.
  for s in b.syms {
    for w in s.params {
      b.note_handle(w)
    }
    b.note_handle(s.ret)
  }
  {
    guest,
    syms: b.syms,
    handles: b.handles,
    skipped: sorted_reasons(b.skipped),
  }
}
