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
#derive(Debug, Eq)
pub(all) struct TyRef {
  /// The MoonBit type expression, e.g. `@json.Position`.
  expr : String
  /// The package that declares the type, so the guest knows which import it
  /// needs and the Python side knows which table tag to send.
  pkg : String
  /// An identifier-safe spelling, e.g. `json_Position`. Used for the table, its
  /// helpers and the Python class attribute.
  key : String
}

///|
/// How one value crosses the boundary.
///
/// Deliberately small. Each variant is one conversion in the guest's decoder and
/// one in the Python codec; adding one is a decision about the ABI, not a
/// convenience for the generator.
#derive(Debug, Eq)
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
  /// `Array[T]` / `FixedArray[T]`, which is a Python `list`.
  ///
  /// Containers are structural, not nominal: `Array[Int]` and `Array[String]`
  /// are the same conversion applied to different elements, so the shape is a
  /// tree and the guest emits one decoder per node in it.
  WArr(Wire)
  /// `ArrayView[T]`: the same bytes as `WArr`, but the guest has to build a
  /// view at the call site. Kept apart because MoonBit does not coerce an
  /// `Array` into an `ArrayView` at a call, and the generator is the only place
  /// that knows which one the callee wants.
  WArrView(Wire)
  /// `Map[K, V]`, which is a Python `dict`. The wire already carries maps as
  /// pairs, so nothing about the format changes.
  WMap(Wire, Wire)
  /// `Result[T, E]` in a return position, where `E` is a `suberror`.
  ///
  /// Python has one way to say "this did not work", and it is an exception, so
  /// `Ok` becomes the value and `Err` becomes a raised `MoonError`. Erasing the
  /// wrapper is the honest mapping: a caller who wants to branch on failure
  /// wraps the call in `try`, exactly as they would for any other Python API.
  WRes(Wire, Wire)
  /// A function value, which the guest invokes through a host import.
  ///
  /// The parameters and the return are themselves wire shapes, so a callback
  /// that takes an array of handles works the same as one that takes an int.
  WCall(Array[Wire], Wire)
}

///|
/// An identifier-safe name for a shape, used to name the decoder and encoder
/// emitted for it: `Array[Int]` is `arr_int`, `Map[String, Array[Int]]` is
/// `map_str_arr_int`.
///
/// Structural rather than generated, because two parameters of the same shape
/// must share one helper — otherwise the guest emits the same function twice
/// and the second definition does not compile.
pub fn Wire::key(self : Wire) -> String {
  match self {
    WInt => "int"
    WDouble => "double"
    WBool => "bool"
    WStr => "str"
    WStrView => "strview"
    WUnit => "unit"
    WMaybe(inner) => "opt_" + inner.key()
    WHandle(t) => t.key
    WArr(inner) => "arr_" + inner.key()
    // The same decoder: a view is built from a list after it is decoded.
    WArrView(inner) => "arr_" + inner.key()
    WMap(k, v) => "map_" + k.key() + "_" + v.key()
    WRes(ok, err) => "res_" + ok.key() + "_" + err.key()
    WCall(params, ret) => {
      let parts : Array[String] = []
      for p in params {
        parts.push(p.key())
      }
      "cb_" + join_strings(parts, "_") + "_to_" + ret.key()
    }
  }
}

///|
/// Whether a shape can cross the callback channel.
///
/// Deliberately narrow. A callback that took a handle would have to guess which
/// side owns it, and one that took an array would need a second copy of the
/// container decoder on a path that has no error channel — a Python exception
/// inside a callback is recorded and re-raised after the outer call returns.
/// Scalars have neither problem.
fn is_callback_shape(w : Wire) -> Bool {
  match w {
    WInt
    | WDouble
    | WBool
    | WStr
    | WUnit
    | WMaybe(WInt)
    | WMaybe(WDouble)
    | WMaybe(WBool)
    | WMaybe(WStr) => true
    _ => false
  }
}

///|
/// What a symbol does, which decides how the guest writes the call.
#derive(Debug, Eq)
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
}

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
#derive(Debug)
pub(all) struct Sym {
  kind : SymKind
  /// The string on the wire, and the only thing the two halves share at
  /// runtime.
  symbol : String
  /// The package that declared it. Not necessarily the receiver's package:
  /// MoonBit allows one package to attach a method to a type it does not own.
  decl_pkg : String
  /// Raw MoonBit type name of the receiver, empty for a free function.
  owner : String
  /// The package the receiver's type belongs to — the alias the guest has to
  /// spell the call with, which is not always `decl_pkg`.
  owner_pkg : String
  /// Raw name of the function or field.
  name : String
  /// Parameter shapes, receiver first when the symbol takes one.
  params : Array[Wire]
  /// One label per parameter, empty when the parameter has none. A function's
  /// optional parameter must be passed by label — MoonBit does not accept it
  /// positionally — and a struct literal must name its fields, so both need the
  /// names kept alongside the shapes.
  labels : Array[String]
  ret : Wire
  raises : Bool
  /// The declared error type of `raise E`, fully qualified, or empty when the
  /// declaration only says `raise`.
  ///
  /// It is what lets Python raise the *generated* exception class instead of a
  /// generic one: `except ParseError` works because the guest names the type it
  /// raised, not because the message was parsed.
  error_type : String
}

///|
/// A concrete type that needs its own handle table.
///
/// One table per type because MoonBit has no runtime type information: a single
/// table would have to store a boxed union, and there is no boxed union. The tag
/// is what lets a release batch name which table an id belongs to.
#derive(Debug)
pub(all) struct HandleSlot {
  ty : TyRef
  /// The number the Python wrapper sends back when releasing. Starts at 1 so
  /// that 0 keeps meaning "no object".
  tag : Int32
}

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
      Some({
        expr: at + "." + q.name,
        pkg: home,
        key: wire_key(at + "." + q.name),
      })
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
      match q.name {
        // `Int32` is the name `moon info` writes for a 32-bit `Int`, and the
        // wire integer is 32 bits wide, so the two are the same shape. A
        // genuine `Int64` is not: it would be truncated, so it stays unmapped.
        "Int" | "Int32" => if args.length() == 0 { Some(WInt) } else { None }
        "Double" | "Float" =>
          if args.length() == 0 {
            Some(WDouble)
          } else {
            None
          }
        "Bool" => if args.length() == 0 { Some(WBool) } else { None }
        "String" => if args.length() == 0 { Some(WStr) } else { None }
        "StringView" => if args.length() == 0 { Some(WStrView) } else { None }
        "Unit" => if args.length() == 0 { Some(WUnit) } else { None }
        "Array" | "FixedArray" =>
          self.single_arg(pkg, args, owner, fn(w) { WArr(w) })
        "ArrayView" =>
          // Read-only by construction, and Python has no way to hand a view
          // over: it sends a list, and the guest builds the view from it.
          self.single_arg(pkg, args, owner, fn(w) { WArrView(w) })
        "Option" =>
          match self.single_arg(pkg, args, owner, fn(w) { WMaybe(w) }) {
            // `T??` is not a shape the frame has.
            Some(WMaybe(WMaybe(_))) => None
            other => other
          }
        "Map" =>
          if args.length() != 2 {
            None
          } else {
            match
              (
                self.wire_in(pkg, args[0], owner),
                self.wire_in(pkg, args[1], owner),
              ) {
              // A `StringView` element borrows from a string that the container
              // does not own, so it cannot outlive the decode. Refusing keeps
              // the guest free of dangling views.
              (Some(k), Some(v)) =>
                if contains_strview(k) || contains_strview(v) {
                  None
                } else {
                  Some(WMap(k, v))
                }
              _ => None
            }
          }
        // `Result` is only readable in a return position: a parameter would
        // have to be built from a Python value, and Python has no `Err`.
        "Result" => None
        _ =>
          if args.length() > 0 {
            None
          } else {
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
    @mbti.Func(params, ret, effect) => {
      // A function value crosses as a callable: Python holds the function, the
      // guest holds an id, and the guest calls back through a wasm import.
      let shapes : Array[Wire] = []
      let mut ok = !effect.raises && !effect.raises_may
      for p in params {
        match self.wire_in(pkg, p.ty, owner) {
          Some(w) => {
            // A handle or an array inside a callback would have to be built on
            // one side and released on the other; the callback channel carries
            // scalars, so that is what it says.
            if !is_callback_shape(w) {
              ok = false
            }
            shapes.push(w)
          }
          None => ok = false
        }
      }
      match self.wire_out(pkg, ret, owner) {
        Some(r) => if ok { Some(WCall(shapes, r)) } else { None }
        None => None
      }
    }
    _ => None
  }
}

///|
/// Whether a shape carries a borrowed string anywhere inside it.
fn contains_strview(w : Wire) -> Bool {
  match w {
    WStrView => true
    WMaybe(inner) | WArr(inner) | WArrView(inner) => contains_strview(inner)
    WMap(k, v) => contains_strview(k) || contains_strview(v)
    WRes(ok, err) => contains_strview(ok) || contains_strview(err)
    WCall(params, ret) => {
      let mut found = contains_strview(ret)
      for p in params {
        if contains_strview(p) {
          found = true
        }
      }
      found
    }
    _ => false
  }
}

///|
/// Applies a one-argument constructor (`Array`, `Option`) to the shape of its
/// argument, or `None` when the arity is wrong.
///
/// The element is resolved with the same owner the container had, so `Array[Self]`
/// inside a method on that type is the handle the method already holds. The
/// borrowed-string check is what keeps that safe: a `StringView` would borrow
/// from a string the container does not own, so it is refused rather than
/// decoded into storage that outlives its source.
fn Builder::single_arg(
  self : Builder,
  pkg : String,
  args : Array[@mbti.TypeExpr],
  owner : TyRef?,
  make : (Wire) -> Wire,
) -> Wire? {
  if args.length() != 1 {
    return None
  }
  match self.wire_in(pkg, args[0], owner) {
    Some(inner) =>
      if contains_strview(inner) {
        None
      } else {
        Some(make(inner))
      }
    None => None
  }
}

///|
/// `FixedArray` and `ArrayView` are wired as `Array[T]`, which is right for a
/// value coming *in* (the guest builds the container from a Python list) but
/// wrong for a value going *out*: the callee hands back a fixed array or a view
/// and MoonBit will not coerce either into an `Array` at the encoder call. The
/// declaration is the only place that says which one it is, so refuse the
/// signature rather than emit a call that does not compile.
fn has_fixed_or_view(ty : @mbti.TypeExpr) -> Bool {
  let names : Array[@mbti.QName] = []
  ty.collect_names(names)
  for q in names {
    if q.name == "FixedArray" || q.name == "ArrayView" {
      return true
    }
  }
  false
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
  if has_fixed_or_view(ty) {
    return None
  }
  match ty {
    @mbti.Optional(inner) =>
      match self.wire_out(pkg, inner, owner) {
        // `T??` is not a shape the frame has; refusing keeps the decoder total.
        Some(WMaybe(_)) => None
        Some(w) => Some(WMaybe(w))
        None => None
      }
    // A `Result` only makes sense on the way out: `Ok` is the value and `Err`
    // is an exception, which is the only failure Python has.
    @mbti.Named(q, args) =>
      if q.name == "Result" && args.length() == 2 {
        match args[1] {
          @mbti.Named(err, err_args) =>
            if err_args.length() == 0 && self.world.is_suberror(pkg, err) {
              match self.wire_out(pkg, args[0], owner) {
                Some(ok) => Some(WRes(ok, WStr))
                None => None
              }
            } else {
              None
            }
          _ => None
        }
      } else {
        self.wire_in(pkg, ty, owner)
      }
    @mbti.Func(_, _, _) =>
      // A callback cannot be a return value: the Python side would have to
      // invent an object for a MoonBit closure to call into, and there is no
      // guest-side callable to hand out.
      None
    _ => self.wire_in(pkg, ty, owner)
  }
}

///|
fn Builder::add(self : Builder, sym : Sym) -> Unit {
  // The same symbol can be reached from two packages when a method is declared
  // away from the type it is attached to, and the guest can only answer it once.
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
  let mut owner_pkg = pkg
  let mut takes_self = false
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
      owner_pkg = self.world.home_of(pkg, r).unwrap_or(pkg)
      owner = Some(slot)
      if f.params.length() > 0 && is_self_ty(f.params[0].ty) {
        // The receiver is passed as argument zero, because that is what the
        // Python side sends: `self` followed by the declared parameters.
        takes_self = true
        rest = drop_receiver(f.params)
      }
    }
    None => ()
  }
  // `Byte::Byte(Byte) -> Byte` and its Int64/UInt16/UInt64/Double siblings are
  // not constructors MoonBit lets us call: those are `pub type X` declarations,
  // and the compiler rejects `Type::Type(...)` on a predefined type. A struct
  // or enum constructor with the same shape (`Point::Point`) is perfectly
  // callable, so the declaration kind is what decides.
  if owner_raw != "" && f.name == owner_raw {
    if self.world.is_predefined(owner_pkg, owner_raw) {
      return self.skip("predefined-ctor")
    }
  }
  let params : Array[Wire] = []
  let labels : Array[String] = []
  // Only a declaration that actually takes a `Self` has a receiver. A
  // `Type::Type(...)` constructor function and a `Type::from_*` builder are
  // associated functions: they produce a value of the type, they do not
  // receive one, and the Python side renders them as static methods.
  if takes_self {
    match owner {
      Some(o) => {
        params.push(WHandle(o))
        labels.push("")
      }
      None => ()
    }
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
    // An optional parameter can only be passed by label, so its name is part
    // of the call, not a comment on it.
    labels.push(
      match p.kind {
        @mbti.Optional => p.name.unwrap_or("")
        _ => ""
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
    owner_pkg,
    name: f.name,
    params,
    labels,
    ret,
    raises: f.effect.raises,
    error_type: {
      let declared = qualified_error(self.world, pkg, f)
      if declared != "" {
        declared
      } else {
        // `Result[T, E]` is the other way a function says what can go wrong, and
        // the Python side raises the same class either way, so the error type
        // has to be recovered from the return type when there is no `raise`.
        result_error_name(self.world, pkg, f.ret)
      }
    },
  })
}

///|
/// The fully qualified error type inside `Result[T, E]`, or empty when the type
/// is not a `Result` over a named error.
fn result_error_name(
  world : @map.World,
  pkg : String,
  ty : @mbti.TypeExpr,
) -> String {
  match ty {
    @mbti.Named(q, args) =>
      if q.name == "Result" && args.length() == 2 {
        match args[1] {
          @mbti.Named(e, _) =>
            world.home_of(pkg, e).unwrap_or(pkg) + "::" + e.name
          _ => ""
        }
      } else {
        ""
      }
    _ => ""
  }
}

///|
/// The fully qualified name of a function's declared error type, or empty when
/// the declaration says only `raise`.
fn qualified_error(
  world : @map.World,
  pkg : String,
  f : @mbti.FuncDecl,
) -> String {
  match f.effect.error {
    Some(@mbti.Named(q, _)) =>
      world.home_of(pkg, q).unwrap_or(pkg) + "::" + q.name
    _ => ""
  }
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
    pkg,
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
  let ctor_labels : Array[String] = []
  let mut ctor_ok = true
  for f in visible {
    match self.wire_in(pkg, f.ty, Some(owner)) {
      Some(w) => {
        ctor_params.push(w)
        ctor_labels.push(f.name)
      }
      None => ctor_ok = false
    }
  }
  if ctor_ok {
    self.add({
      kind: Ctor,
      symbol: ctor_symbol(pkg, s.name),
      decl_pkg: pkg,
      owner: s.name,
      owner_pkg: pkg,
      name: "__new__",
      params: ctor_params,
      labels: ctor_labels,
      ret: WHandle(owner),
      raises: false,
      error_type: "",
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
          owner_pkg: pkg,
          name: f.name,
          params: [WHandle(owner)],
          labels: [f.name],
          ret: w,
          raises: false,
          error_type: "",
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
            owner_pkg: pkg,
            name: f.name,
            params: [WHandle(owner), w],
            labels: [f.name, ""],
            ret: WUnit,
            raises: false,
            error_type: "",
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
