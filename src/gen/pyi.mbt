//! Python stub generation.
//!
//! Input: one parsed `.mbti` file. Output: one `.pyi` file plus counters.
//!
//! The generator is deliberately conservative. A stub is a promise to the type
//! checker, so anything this module cannot express is left out of the stub
//! rather than approximated: private declarations vanish, methods on foreign
//! types are dropped, and unrepresentable types become `Any` through
//! `@map.Mapper`, which records why.
//!
//! A stub never imports another generated stub. Cross-package types therefore
//! arrive as `Any` from the mapper, which keeps every `.pyi` independently
//! checkable and avoids the import cycles that a MoonBit package graph happily
//! contains.

///|
/// Knobs the generator needs; kept in a struct so tests can pin the import
/// path without touching production text.
pub(all) struct GenOptions {
  /// Module that provides the handle base class.
  runtime_module : String
  /// Base class of every generated handle type.
  base_class : String
  /// Base class of every generated error type.
  error_base : String
} derive(Debug, Eq)

///|
pub fn GenOptions::standard() -> GenOptions {
  {
    runtime_module: "moonbridge._runtime",
    base_class: "MoonObject",
    error_base: "MoonError",
  }
}

///|
/// One generated stub plus what it took to produce it.
pub(all) struct Stub {
  module_name : String
  filename : String
  text : String
  /// Classes, including errors, traits and opaque types.
  types : Int32
  /// Module-level functions, `pub let`s and constants.
  funcs : Int32
  /// Class fields exposed as properties.
  fields : Int32
  /// Declarations this generator could not express.
  skipped : Int32
  /// Type positions degraded to `Any`, by reason.
  degraded : Array[@map.Degrade]
}

///|
/// Renders the stub for one package.
pub fn generate(pkg : @mbti.Package, opts : GenOptions) -> Stub {
  let em : Emitter = {
    opts,
    pkg_name: pkg.name,
    mapper: @map.Mapper::for_package(pkg),
    blocks: [],
    methods: Map([]),
    emitted: Map([]),
    typevars: [],
    typing_used: Map([]),
    need_base: false,
    need_error: false,
    type_count: 0,
    func_count: 0,
    field_count: 0,
    skipped: 0,
  }
  // Pass one: index `Type::method` declarations by receiver, so a class can be
  // rendered with its methods in place even though they appear later in the
  // interface.
  for decl in pkg.decls {
    match decl {
      @mbti.Decl::Func(f) =>
        match f.receiver {
          Some(r) => {
            let bucket = match em.methods.get(r.name) {
              Some(b) => b
              None => {
                let b : Array[@mbti.FuncDecl] = []
                em.methods.set(r.name, b)
                b
              }
            }
            bucket.push(f)
          }
          None => ()
        }
      _ => ()
    }
  }
  // Pass two: emit in source order.
  for decl in pkg.decls {
    em.decl(decl)
  }
  let text = em.assemble()
  {
    module_name: @map.module_stem(pkg.name),
    filename: @map.stub_filename(pkg.name),
    text,
    types: em.type_count,
    funcs: em.func_count,
    fields: em.field_count,
    skipped: em.skipped,
    degraded: em.mapper.degraded,
  }
}

///|
/// Generation state. Fields are mutable because rendering a class requires
/// knowing which typing helpers ended up in its annotations.
priv struct Emitter {
  opts : GenOptions
  pkg_name : String
  mapper : @map.Mapper
  /// Finished top-level blocks, in source order.
  blocks : Array[String]
  /// `Type` -> methods declared as `Type::method`.
  methods : Map[String, Array[@mbti.FuncDecl]]
  /// Top-level names already taken; first declaration wins.
  emitted : Map[String, Bool]
  /// Type variables in first-use order.
  typevars : Array[String]
  /// typing names referenced by at least one annotation.
  typing_used : Map[String, Bool]
  mut need_base : Bool
  mut need_error : Bool
  mut type_count : Int32
  mut func_count : Int32
  mut field_count : Int32
  mut skipped : Int32
}

///|
fn is_self_ty(ty : @mbti.TypeExpr) -> Bool {
  match ty {
    @mbti.TypeExpr::SelfType(_) => true
    _ => false
  }
}

///|
/// The python name of a member. An associated function named after its own
/// type would shadow the class inside its own body, so `fn T::T` becomes
/// `T.new`.
fn member_name(f : @mbti.FuncDecl, owner : String) -> String {
  let name = @map.stub_name(f.name)
  if name == owner {
    "new"
  } else {
    name
  }
}

///|
/// `.mbti` prints the receiver as an explicit leading `Self` parameter:
/// `fn Point::norm(Self) -> Double`. The stub turns it into Python's `self`,
/// so the parameter list must lose that first entry.
fn drop_receiver(params : Array[@mbti.Param]) -> Array[@mbti.Param] {
  let out : Array[@mbti.Param] = []
  let mut first = true
  for p in params {
    if first && is_self_ty(p.ty) {
      first = false
      continue
    }
    first = false
    out.push(p)
  }
  out
}

///|
fn join(items : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut first = true
  for item in items {
    if !first {
      sb.write_string(sep)
    }
    sb.write_string(item)
    first = false
  }
  sb.to_string()
}

///|
/// Records the typing helpers an annotation needs.
fn track_typing(used : Map[String, Bool], ty : @map.PyType) -> Unit {
  match ty {
    @map.PyAny => used.set("Any", true)
    @map.PyOptional(inner) => {
      used.set("Optional", true)
      track_typing(used, inner)
    }
    @map.PySeq(inner) => {
      used.set("Sequence", true)
      track_typing(used, inner)
    }
    @map.PyList(inner) => track_typing(used, inner)
    @map.PyDict(k, v) => {
      track_typing(used, k)
      track_typing(used, v)
    }
    @map.PyTuple(items) => items.each(fn(t) { track_typing(used, t) })
    @map.PyHandle(_, args) => args.each(fn(t) { track_typing(used, t) })
    _ => ()
  }
}

///|
fn Emitter::claim(self : Emitter, name : String) -> Bool {
  if self.emitted.contains(name) {
    self.skipped = self.skipped + 1
    false
  } else {
    self.emitted.set(name, true)
    true
  }
}

///|
fn Emitter::typevar(self : Emitter, raw : String) -> String {
  let name = @map.stub_name(raw)
  if !self.typevars.contains(name) {
    self.typevars.push(name)
  }
  name
}

///|
fn Emitter::decl(self : Emitter, decl : @mbti.Decl) -> Unit {
  match decl {
    @mbti.Decl::Struct(s) =>
      match self.render_struct(s) {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Enum(e) =>
      match self.render_enum(e.name, e.generics, e.ctors, e.access, "enum") {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Error(e) =>
      match
        self.render_enum(e.name, e.generics, e.ctors, e.access, "suberror") {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Trait(t) =>
      match self.render_trait(t) {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Opaque(o) =>
      match self.render_opaque(o) {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Alias(a) =>
      match self.render_alias(a) {
        Some(block) => self.blocks.push(block)
        None => self.skipped = self.skipped + 1
      }
    @mbti.Decl::Func(f) =>
      match f.receiver {
        // Already rendered inside its class in pass two; a receiver that has no
        // class in this package has no place to live.
        Some(_) => ()
        None =>
          match self.render_func(f, None, None) {
            Some(block) => {
              self.blocks.push(block)
              self.func_count = self.func_count + 1
            }
            None => self.skipped = self.skipped + 1
          }
      }
    @mbti.Decl::Value(v) =>
      if self.claim(@map.stub_name(v.name)) {
        let scoped = self.mapper.for_decl([], None)
        let ty = scoped.map(v.ty)
        self.note_type(ty)
        self.blocks.push(@map.stub_name(v.name) + ": " + ty.render())
        self.func_count = self.func_count + 1
      }
    @mbti.Decl::Const(c) =>
      if self.claim(@map.stub_name(c.name)) {
        let scoped = self.mapper.for_decl([], None)
        let ty = scoped.map(c.ty)
        self.note_type(ty)
        self.blocks.push(@map.stub_name(c.name) + ": " + ty.render())
        self.func_count = self.func_count + 1
      }
    @mbti.Decl::Impl(_) => ()
    @mbti.Decl::Reexport(r) => self.render_reexport(r)
  }
}

///|
/// Records the typing helpers a type needs and the type variables it mentions.
fn Emitter::note_type(self : Emitter, ty : @map.PyType) -> Unit {
  track_typing(self.typing_used, ty)
  self.note_vars(ty)
}

///|
fn Emitter::note_vars(self : Emitter, ty : @map.PyType) -> Unit {
  match ty {
    @map.PyVar(name) =>
      if !self.typevars.contains(name) {
        self.typevars.push(name)
      }
    @map.PyList(inner) | @map.PySeq(inner) | @map.PyOptional(inner) =>
      self.note_vars(inner)
    @map.PyDict(k, v) => {
      self.note_vars(k)
      self.note_vars(v)
    }
    @map.PyTuple(items) | @map.PyHandle(_, items) =>
      items.each(fn(t) { self.note_vars(t) })
    _ => ()
  }
}

///|
fn Emitter::class_header(
  self : Emitter,
  name : String,
  generics : Array[@mbti.GenericParam],
  bases : Array[String],
  is_error : Bool,
  include_base : Bool,
) -> String {
  let all : Array[String] = []
  if is_error {
    self.need_error = true
    all.push(self.opts.error_base)
  } else if include_base {
    self.need_base = true
    all.push(self.opts.base_class)
  }
  for b in bases {
    all.push(b)
  }
  if generics.length() > 0 {
    self.typing_used.set("Generic", true)
    let args : Array[String] = []
    for g in generics {
      args.push(self.typevar(g.name))
    }
    all.push("Generic[" + join(args, ", ") + "]")
  }
  "class " + name + "(" + join(all, ", ") + "):"
}

///|
fn render_doc(indent : String, text : String) -> String {
  indent + "\"\"\"" + text + "\"\"\""
}

///|
fn body_of(doc : String, members : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_string(render_doc("    ", doc))
  for m in members {
    sb.write_string("\n")
    sb.write_string(m)
  }
  sb.to_string()
}

///|
/// Renders `def name(<params>) -> <ret>: ...` with the mapping context already
/// scoped to the declaring type.
fn Emitter::signature(
  self : Emitter,
  name : String,
  is_method : Bool,
  scoped : @map.Mapper,
  fn_generics : Array[@mbti.GenericParam],
  params : Array[@mbti.Param],
  ret : @map.PyType,
) -> String {
  let used : Map[String, Bool] = Map([])
  if is_method {
    used.set("self", true)
  }
  let types : Array[@map.PyType] = []
  let names : Array[String] = []
  let mut index = 0
  for p in params {
    let ty = scoped.map(p.ty)
    self.note_type(ty)
    types.push(ty)
    let base = match p.name {
      Some(n) => @map.stub_name(n)
      None => "arg" + index.to_string()
    }
    // Two parameters can share a name in MoonBit (one positional, one
    // labelled); Python would reject the duplicate.
    let mut pname = base
    let mut suffix = 2
    while used.contains(pname) {
      pname = base + "_" + suffix.to_string()
      suffix = suffix + 1
    }
    used.set(pname, true)
    names.push(pname)
    index = index + 1
  }
  // A TypeVar that appears only in the return type cannot be inferred from the
  // call, and mypy rejects the signature outright. Degrade that position to
  // Any instead of shipping a stub that cannot type-check.
  let bound : Map[String, Bool] = Map([])
  for ty in types {
    ty.collect_vars(bound)
  }
  let fn_vars : Map[String, Bool] = Map([])
  for g in fn_generics {
    fn_vars.set(@map.stub_name(g.name), true)
  }
  let ret_ty = ret.drop_unbound(fn_vars, bound)
  self.note_type(ret_ty)
  let pos : Array[String] = []
  let kw : Array[String] = []
  if is_method {
    pos.push("self")
  }
  let mut i = 0
  while i < types.length() {
    match params[i].kind {
      @mbti.Positional => pos.push(names[i] + ": " + types[i].render())
      @mbti.Optional => {
        let ann = match types[i] {
          @map.PyOptional(_) => types[i].render()
          _ => {
            self.typing_used.set("Optional", true)
            "Optional[" + types[i].render() + "]"
          }
        }
        kw.push(names[i] + ": " + ann + " = ...")
      }
      @mbti.Labeled => kw.push(names[i] + ": " + types[i].render())
    }
    i = i + 1
  }
  let sb = StringBuilder()
  sb.write_string("def " + name + "(")
  if pos.length() > 0 {
    // MoonBit positional parameters cannot be passed by keyword, so the stub
    // marks them positional-only instead of inventing keyword names.
    sb.write_string(join(pos, ", ") + ", /")
  }
  if kw.length() > 0 {
    if pos.length() > 0 {
      sb.write_string(", ")
    }
    sb.write_string("*")
    sb.write_string(", " + join(kw, ", "))
  }
  sb.write_string(") -> " + ret_ty.render() + ": ...")
  sb.to_string()
}

///|
fn Emitter::render_func(
  self : Emitter,
  f : @mbti.FuncDecl,
  owner : String?,
  forced : String?,
) -> String? {
  let scoped = self.mapper.for_decl(f.generics, owner)
  let ret = scoped.map(f.ret)
  self.note_type(ret)
  match owner {
    Some(owner_name) => {
      let mut has_receiver = false
      if f.params.length() > 0 {
        has_receiver = is_self_ty(f.params[0].ty)
      }
      let params = if has_receiver { drop_receiver(f.params) } else { f.params }
      let name = match forced {
        Some(n) => n
        None => member_name(f, owner_name)
      }
      let rendered = self.signature(
        name,
        has_receiver,
        scoped,
        f.generics,
        params,
        ret,
      )
      if has_receiver {
        Some("    " + rendered)
      } else {
        // `fn T::new(...)` is an associated function, not a method: it takes no
        // receiver, so the stub must not add one.
        Some("    @staticmethod\n    " + rendered)
      }
    }
    None => {
      let name = match forced {
        Some(n) => n
        None => @map.stub_name(f.name)
      }
      if self.claim(name) {
        Some(self.signature(name, false, scoped, f.generics, f.params, ret))
      } else {
        None
      }
    }
  }
}

///|
fn Emitter::render_struct(self : Emitter, s : @mbti.StructDecl) -> String? {
  if s.access == @mbti.Private {
    return None
  }
  let name = @map.stub_name(s.name)
  if !self.claim(name) {
    return None
  }
  self.type_count = self.type_count + 1
  let scoped = self.mapper.for_decl(s.generics, Some(name))
  let visible : Array[@mbti.Field] = []
  for f in s.fields {
    if f.access != @mbti.Private {
      visible.push(f)
    }
  }
  // Positional fields have no MoonBit name, so the Python name is derived from
  // position once and reused by both `__init__` and the property.
  let field_names : Array[String] = []
  let mut pos_index = 0
  for f in visible {
    if f.name == "" {
      field_names.push("field" + pos_index.to_string())
      pos_index = pos_index + 1
    } else {
      field_names.push(@map.stub_name(f.name))
    }
  }
  let members : Array[String] = []
  // A struct with hidden fields cannot be constructed from Python: the stub
  // still exposes the public fields, but offers no `__init__` that would
  // promise construction is possible.
  if s.access == @mbti.Open && !s.has_hidden_fields {
    let ctor_params : Array[String] = ["self"]
    let mut i = 0
    while i < visible.length() {
      let ty = scoped.map(visible[i].ty)
      self.note_type(ty)
      ctor_params.push(field_names[i] + ": " + ty.render())
      i = i + 1
    }
    members.push(
      "    def __init__(" + join(ctor_params, ", ") + ") -> None: ...",
    )
  }
  let mut i = 0
  while i < visible.length() {
    let f = visible[i]
    let ty = scoped.map(f.ty)
    self.note_type(ty)
    self.field_count = self.field_count + 1
    members.push("    @property")
    members.push(
      "    def " + field_names[i] + "(self) -> " + ty.render() + ": ...",
    )
    if f.is_mut {
      members.push("    @" + field_names[i] + ".setter")
      members.push(
        "    def " +
        field_names[i] +
        "(self, value: " +
        ty.render() +
        ") -> None: ...",
      )
    }
    i = i + 1
  }
  let taken : Map[String, Bool] = Map([])
  for fname in field_names {
    taken.set(fname, true)
  }
  self.attach_methods(name, members, taken)
  let header = self.class_header(name, s.generics, [], false, true)
  Some(header + "\n" + body_of("MoonBit struct `" + s.name + "`.", members))
}

///|
fn Emitter::attach_methods(
  self : Emitter,
  class_name : String,
  members : Array[String],
  taken : Map[String, Bool],
) -> Unit {
  let key = match self.receiver_key(class_name) {
    Some(k) => k
    None => return
  }
  match self.methods.get(key) {
    None => ()
    Some(list) =>
      for f in list {
        let base = member_name(f, class_name)
        // A field and a method may share a name in MoonBit, where the compiler
        // tells them apart by call syntax. Python has one namespace, so the
        // method moves aside rather than disappearing.
        let mut name = base
        let mut suffix = 2
        while taken.contains(name) {
          name = base + "_" + suffix.to_string()
          suffix = suffix + 1
        }
        taken.set(name, true)
        match self.render_func(f, Some(class_name), Some(name)) {
          Some(text) => members.push(text)
          None => self.skipped = self.skipped + 1
        }
      }
  }
}

///|
/// Maps a Python class name back to the MoonBit receiver name it stands for.
fn Emitter::receiver_key(self : Emitter, class_name : String) -> String? {
  for name in self.methods.keys() {
    if @map.stub_name(name) == class_name {
      return Some(name)
    }
  }
  None
}

///|
fn Emitter::render_enum(
  self : Emitter,
  raw_name : String,
  generics : Array[@mbti.GenericParam],
  ctors : Array[@mbti.Ctor],
  access : @mbti.Access,
  kind : String,
) -> String? {
  if access == @mbti.Private {
    return None
  }
  let name = @map.stub_name(raw_name)
  if !self.claim(name) {
    return None
  }
  self.type_count = self.type_count + 1
  let is_error = kind == "suberror"
  let scoped = self.mapper.for_decl(generics, Some(name))
  let members : Array[String] = []
  if ctors.length() == 1 && ctors[0].fields.length() > 0 {
    let ctor_params : Array[String] = ["self"]
    let mut index = 0
    for f in ctors[0].fields {
      let fname = if f.name != "" {
        @map.stub_name(f.name)
      } else if is_error && index == 0 {
        // The first payload of an error carries the message; naming it makes
        // `raise ParseError("...")` readable.
        "message"
      } else {
        "field" + index.to_string()
      }
      let ty = scoped.map(f.ty)
      self.note_type(ty)
      ctor_params.push(fname + ": " + ty.render())
      index = index + 1
    }
    members.push(
      "    def __init__(" + join(ctor_params, ", ") + ") -> None: ...",
    )
  } else if ctors.length() > 1 || is_error {
    // Several payload shapes cannot be described by one signature; the tag
    // plus an open payload is the honest common denominator.
    self.typing_used.set("Any", true)
    members.push("    def __init__(self, tag: str, *args: Any) -> None: ...")
  }
  if ctors.length() > 0 {
    members.push("    @property")
    members.push("    def tag(self) -> str: ...")
  }
  let taken : Map[String, Bool] = Map([])
  if ctors.length() > 0 {
    taken.set("tag", true)
  }
  self.attach_methods(name, members, taken)
  let header = self.class_header(name, generics, [], is_error, true)
  Some(
    header + "\n" + body_of("MoonBit " + kind + " `" + raw_name + "`.", members),
  )
}

///|
fn Emitter::render_trait(self : Emitter, t : @mbti.TraitDecl) -> String? {
  if t.access == @mbti.Private {
    return None
  }
  let name = @map.stub_name(t.name)
  if !self.claim(name) {
    return None
  }
  self.type_count = self.type_count + 1
  self.typing_used.set("Protocol", true)
  let members : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for m in t.methods {
    let mname = @map.stub_name(m.name)
    if seen.contains(mname) {
      continue
    }
    seen.set(mname, true)
    let scoped = self.mapper.for_decl(
      concat_generics(t.generics, m.generics),
      Some(name),
    )
    let ret = scoped.map(m.ret)
    self.note_type(ret)
    members.push(
      "    " +
      self.signature(
        mname,
        true,
        scoped,
        m.generics,
        drop_receiver(m.params),
        ret,
      ),
    )
  }
  let header = self.class_header(name, t.generics, ["Protocol"], false, false)
  Some(header + "\n" + body_of("MoonBit trait `" + t.name + "`.", members))
}

///|
fn Emitter::render_opaque(self : Emitter, o : @mbti.OpaqueDecl) -> String? {
  if o.access == @mbti.Private {
    return None
  }
  let name = @map.stub_name(o.name)
  if !self.claim(name) {
    return None
  }
  self.type_count = self.type_count + 1
  let members : Array[String] = []
  let taken : Map[String, Bool] = Map([])
  self.attach_methods(name, members, taken)
  let header = self.class_header(name, o.generics, [], false, true)
  Some(
    header +
    "\n" +
    body_of(
      "Opaque MoonBit type `" + o.name + "`; the representation is not exposed.",
      members,
    ),
  )
}

///|
fn Emitter::render_alias(self : Emitter, a : @mbti.AliasDecl) -> String? {
  if a.access == @mbti.Private {
    return None
  }
  let name = @map.stub_name(a.name)
  if !self.claim(name) {
    return None
  }
  self.type_count = self.type_count + 1
  // An alias names a type, not a handle, so resolve the target through the
  // mapper: `type Fd = Int` becomes a real Python alias to `int` instead of a
  // reference to a class that is never generated.
  let scoped = self.mapper.for_decl(a.generics, None)
  let target = scoped.map(a.target)
  self.note_type(target)
  self.typing_used.set("TypeAlias", true)
  Some(name + ": TypeAlias = " + target.render())
}

///|
fn Emitter::render_reexport(self : Emitter, r : @mbti.ReexportDecl) -> Unit {
  for entry in r.entries {
    if entry.kind != "type" {
      continue
    }
    let name = @map.stub_name(entry.as_name.unwrap_or(entry.name))
    if !self.claim(name) {
      continue
    }
    // The real class lives in another package, which this stub does not import.
    self.typing_used.set("Any", true)
    self.typing_used.set("TypeAlias", true)
    self.blocks.push(name + ": TypeAlias = Any")
  }
}

///|
fn concat_generics(
  a : Array[@mbti.GenericParam],
  b : Array[@mbti.GenericParam],
) -> Array[@mbti.GenericParam] {
  let out : Array[@mbti.GenericParam] = []
  for g in a {
    out.push(g)
  }
  for g in b {
    out.push(g)
  }
  out
}

///|
/// Assembles the final file: docstring, imports, type variables, body.
fn Emitter::assemble(self : Emitter) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "\"\"\"Type stubs for the MoonBit package `" +
    self.pkg_name +
    "`.\n\n" +
    "Generated by MoonBridge from `pkg.generated.mbti`. Do not edit by hand.\n" +
    "\"\"\"\n",
  )
  let typing_names : Array[String] = []
  for
    name in ["Any", "Generic", "Optional", "Protocol", "Sequence", "TypeAlias"] {
    if self.typing_used.contains(name) {
      typing_names.push(name)
    }
  }
  if self.typevars.length() > 0 {
    typing_names.push("TypeVar")
  }
  if typing_names.length() > 0 {
    sb.write_string("\nfrom typing import " + join(typing_names, ", ") + "\n")
  }
  let runtime : Array[String] = []
  if self.need_error {
    runtime.push(self.opts.error_base)
  }
  if self.need_base {
    runtime.push(self.opts.base_class)
  }
  // Keep the import list stable regardless of which class a package happens to
  // use first, so regenerating an unchanged package produces identical bytes.
  if runtime.length() == 2 && runtime[1] < runtime[0] {
    let first = runtime[0]
    runtime[0] = runtime[1]
    runtime[1] = first
  }
  if runtime.length() > 0 {
    sb.write_string(
      "\nfrom " +
      self.opts.runtime_module +
      " import " +
      join(runtime, ", ") +
      "\n",
    )
  }
  if self.typevars.length() > 0 {
    sb.write_string("\n")
    for v in self.typevars {
      sb.write_string(v + " = TypeVar(\"" + v + "\")\n")
    }
  }
  for block in self.blocks {
    sb.write_string("\n\n")
    sb.write_string(block)
  }
  sb.write_string("\n")
  sb.to_string()
}
