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
/// What kind of file is being rendered.
///
/// A stub is a promise; a module is the thing that keeps it. Both come from the
/// same walk over the same interface, so their signatures cannot disagree.
#derive(Debug, Eq)
pub(all) enum Output {
  /// `.pyi`: signatures only, checked by the type checker.
  Stub
  /// `.py`: the same signatures with a body that calls the guest.
  Bind
}

///|
/// Knobs the generator needs; kept in a struct so tests can pin the import
/// path without touching production text.
#derive(Debug, Eq)
pub(all) struct GenOptions {
  /// Module that provides the handle base class.
  runtime_module : String
  /// Base class of every generated handle type.
  base_class : String
  /// Base class of every generated error type.
  error_base : String
}

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
  /// Module stems this stub imports, sorted. Empty for a self-contained
  /// package, which is still the common case.
  imports : Array[String]
}

///|
/// Renders the stub for one package with no knowledge of its neighbours.
///
/// Every cross-package type degrades to `Any`, which keeps the stub
/// independently checkable. Useful for tests and for a single-package run.
pub fn generate(pkg : @mbti.Package, opts : GenOptions) -> Stub {
  generate_with(None, pkg, opts)
}

///|
/// Renders the stub for one package inside a world.
///
/// With a world, `@json.Json` becomes `_moonbitlang__core__json.Json` and the
/// stub imports that module, so the type checker sees the real class instead
/// of `Any`. Stub modules may import each other in a cycle: Python never
/// executes a `.pyi`, and the type checker resolves the cycle itself.
pub fn generate_with(
  world : @map.World?,
  pkg : @mbti.Package,
  opts : GenOptions,
) -> Stub {
  render(world, pkg, None, opts, Stub)
}

///|
/// Renders the callable module for one package.
///
/// Same declarations, same symbols, same annotations as the stub, with bodies
/// that encode the arguments, call the guest, and decode the answer. A module
/// is only worth generating for a package whose guest is actually compiled,
/// which is why this is a separate entry point rather than the default.
pub fn bind_with(
  world : @map.World?,
  pkg : @mbti.Package,
  plan : Plan?,
  opts : GenOptions,
) -> Stub {
  render(world, pkg, plan, opts, Bind)
}

///|
fn render(
  world : @map.World?,
  pkg : @mbti.Package,
  plan : Plan?,
  opts : GenOptions,
  output : Output,
) -> Stub {
  let mapper = match world {
    Some(w) => @map.Mapper::for_world(w, pkg.name, None)
    None => @map.Mapper::for_package(pkg)
  }
  let em : Emitter = {
    opts,
    output,
    pkg_name: pkg.name,
    world,
    plan,
    mapper,
    blocks: [],
    methods: Map([]),
    emitted: Map([]),
    typevars: [],
    typing_used: Map([]),
    need_base: false,
    need_error: false,
    errors: [],
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
    filename: match output {
      Stub => @map.stub_filename(pkg.name)
      Bind => @map.module_stem(pkg.name) + ".py"
    },
    text,
    types: em.type_count,
    funcs: em.func_count,
    fields: em.field_count,
    skipped: em.skipped,
    degraded: em.mapper.degraded,
    imports: em.mapper.imports(),
  }
}

///|
/// Generation state. Fields are mutable because rendering a class requires
/// knowing which typing helpers ended up in its annotations.
priv struct Emitter {
  opts : GenOptions
  output : Output
  pkg_name : String
  world : @map.World?
  /// What the guest can answer. `None` in stub mode: a stub declares the whole
  /// interface whether or not anything is compiled behind it.
  plan : Plan?
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
  /// `(raw MoonBit name, Python class name)` for every error type this module
  /// defines. The guest names a failure by its fully qualified MoonBit name, so
  /// the module has to publish the mapping at import time or the runtime cannot
  /// raise anything more specific than `MoonError`.
  errors : Array[(String, String)]
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
    @map.PyCallable(params, ret) => {
      used.set("Callable", true)
      params.each(fn(t) { track_typing(used, t) })
      track_typing(used, ret)
    }
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
          match
            self.render_func(f, None, None, self.pkg_name, None, self.mapper) {
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
    @map.PyCallable(params, ret) => {
      params.each(fn(t) { self.note_vars(t) })
      self.note_vars(ret)
    }
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
  // A stub is checked against `from moonbridge._runtime import MoonObject`, a
  // module is executed and reaches the same names through `from . import
  // _runtime`. Both spell the base class the same way to the reader; only the
  // import differs.
  let prefix = match self.output {
    Stub => ""
    Bind => "_runtime."
  }
  if is_error {
    self.need_error = true
    all.push(prefix + self.opts.error_base)
  } else if include_base {
    self.need_base = true
    all.push(prefix + self.opts.base_class)
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
/// A rendered signature plus the parameter names it bound, so the runtime
/// renderer can pass them on without re-parsing its own output.
priv struct Sig {
  text : String
  names : Array[String]
  /// The return type as it was actually written, after a type variable that
  /// could not be inferred was degraded. The body has to agree with the
  /// signature, not with what the interface wanted.
  ret : @map.PyType
}

///|
/// Renders `def name(<params>) -> <ret>`, without the trailing colon: the stub
/// appends `: ...` and the runtime module appends a body.
fn Emitter::signature(
  self : Emitter,
  name : String,
  is_method : Bool,
  scoped : @map.Mapper,
  fn_generics : Array[@mbti.GenericParam],
  params : Array[@mbti.Param],
  ret : @map.PyType,
) -> Sig {
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
  let all_names : Array[String] = []
  if is_method {
    pos.push("self")
    all_names.push("self")
  }
  for n in names {
    all_names.push(n)
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
        // In a stub `= ...` reads as "some default exists". Executed, it would
        // be a default of `Ellipsis`, which the codec cannot encode, so the
        // module spells the only value MoonBit's `?` can represent.
        let default = match self.output {
          Stub => "..."
          Bind => "None"
        }
        kw.push(names[i] + ": " + ann + " = " + default)
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
  sb.write_string(") -> " + ret_ty.render())
  { text: sb.to_string(), names: all_names, ret: ret_ty, }
}

///|
/// The import line that makes a module-qualified class available, or `None`
/// when the name is local.
///
/// A module reference is spelled `_<stem>.<Class>` by the mapper, so the module
/// alias and the module name are one substitution apart.
fn sibling_import(name : String) -> String? {
  let parts = name.split(".").to_array()
  if parts.length() != 2 {
    return None
  }
  let module_name = parts[0].to_owned()
  if module_name.length() == 0 || module_name[0] != '_' {
    return None
  }
  Some(
    "from . import " +
    module_name.exact_view(start=1).to_owned() +
    " as " +
    module_name,
  )
}

///|
/// Closes a signature: a stub gets `...`, a runtime module gets a body that
/// calls the guest.
fn Emitter::finish(
  self : Emitter,
  sig : Sig,
  symbol : String,
  indent : String,
) -> String {
  match self.output {
    Stub => sig.text + ": ..."
    Bind => {
      let ret = sig.ret
      let call = "_runtime.default().request(\"" +
        symbol +
        "\", [" +
        join(self.call_args(symbol, sig.names), ", ") +
        "])"
      let body : Array[String] = []
      match ret {
        // A `Unit` return must not be `return <Any>`, which a strict checker
        // rejects in a function declared `-> None`.
        @map.PyNone => {
          body.push(call)
          body.push("return None")
        }
        @map.PyHandle(name, _) => {
          // The class may live in a module that is still importing this one,
          // so it is fetched at call time rather than bound at import time.
          match sibling_import(name) {
            Some(line) => body.push(line)
            None => ()
          }
          body.push("return _runtime.wrap(" + name + ", " + call + ")")
        }
        _ => {
          // `request` is typed `Any`, and a strict checker rejects returning
          // that from a function with a real return type. `cast` is the honest
          // form of the claim the ABI already makes: the frame carries exactly
          // the value the signature names.
          self.typing_used.set("cast", true)
          body.push("return cast(" + ret.render() + ", " + call + ")")
        }
      }
      let sb = StringBuilder()
      sb.write_string(sig.text + ":")
      for line in body {
        sb.write_string("\n" + indent + line)
      }
      sb.to_string()
    }
  }
}

///|
fn Emitter::render_func(
  self : Emitter,
  f : @mbti.FuncDecl,
  owner : String?,
  owner_raw : String?,
  decl_pkg : String,
  forced : String?,
  base : @map.Mapper,
) -> String? {
  let scoped = base.for_decl(f.generics, owner)
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
      let sig = self.signature(
        name,
        has_receiver,
        scoped,
        f.generics,
        params,
        ret,
      )
      let raw = match owner_raw {
        Some(r) => r
        None => owner_name
      }
      let symbol = decl_pkg + "::" + raw + "::" + f.name
      // A module only carries what the guest can answer. A declaration the
      // planner left out has no branch behind it, so a body here would fail at
      // the call site instead of at generation time.
      if self.output == Bind && !self.has_symbol(symbol) {
        self.skipped = self.skipped + 1
        return None
      }
      let rendered = self.finish(sig, symbol, "        ")
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
      let symbol = self.pkg_name + "::" + f.name
      if self.output == Bind && !self.has_symbol(symbol) {
        self.skipped = self.skipped + 1
        return None
      }
      if self.claim(name) {
        let sig = self.signature(name, false, scoped, f.generics, f.params, ret)
        Some(self.finish(sig, symbol, "    "))
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
  // The table tag travels with the class: a release batch names it, because an
  // id is only unique within one table and the guest holds one per type.
  match self.tag_member(s.name) {
    Some(line) => members.push(line)
    None => ()
  }
  // A struct with hidden fields cannot be constructed from Python: the stub
  // still exposes the public fields, but offers no `__init__` that would
  // promise construction is possible.
  if s.access == @mbti.Open && !s.has_hidden_fields {
    let ctor = ctor_symbol(self.pkg_name, s.name)
    let ctor_params : Array[String] = ["self"]
    let mut i = 0
    while i < visible.length() {
      let ty = scoped.map(visible[i].ty)
      self.note_type(ty)
      // A positional field has no MoonBit name, so no literal can be written
      // for it and the constructor has no symbol. The annotation is still
      // recorded, so the stub keeps the full picture.
      let label = if visible[i].name == "" {
        "field" + i.to_string()
      } else {
        @map.stub_name(visible[i].name)
      }
      ctor_params.push(label + ": " + ty.render())
      i = i + 1
    }
    match self.output {
      Stub =>
        members.push(
          "    def __init__(" + join(ctor_params, ", ") + ") -> None: ...",
        )
      Bind =>
        if self.has_symbol(ctor) {
          // Construction goes through the guest: the object it makes is the
          // object this wrapper stands for, so the handle it returns is taken
          // over rather than copied.
          //
          // A constructor symbol only exists when every field is named, so the
          // Python parameter names are the field names in order.
          let call = "_runtime.default().request(\"" +
            ctor +
            "\", [" +
            join(field_names, ", ") +
            "])"
          self.typing_used.set("cast", true)
          members.push(
            "    def __init__(" +
            join(ctor_params, ", ") +
            ") -> None:\n" +
            "        super().__init__(" +
            "cast(int, " +
            call +
            "), _runtime.default())",
          )
        } else {
          self.skipped = self.skipped + 1
        }
    }
  }
  let mut i = 0
  while i < visible.length() {
    let f = visible[i]
    let ty = scoped.map(f.ty)
    self.note_type(ty)
    self.field_count = self.field_count + 1
    let member_name = if f.name == "" {
      "field" + i.to_string()
    } else {
      f.name
    }
    match self.output {
      Stub => {
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
      }
      Bind => {
        // A read is a symbol like any other; without one the module would fail
        // at the call site, so the member is left out instead.
        let getter = getter_symbol(self.pkg_name, s.name, member_name)
        let setter = setter_symbol(self.pkg_name, s.name, member_name)
        if self.has_symbol(getter) {
          members.push("    @property")
          members.push(
            "    " +
            self.finish(
              {
                text: "def " + field_names[i] + "(self) -> " + ty.render(),
                names: ["self"],
                ret: ty,
              },
              getter,
              "        ",
            ),
          )
        } else {
          self.skipped = self.skipped + 1
        }
        if f.is_mut {
          if self.has_symbol(setter) {
            members.push("    @" + field_names[i] + ".setter")
            members.push(
              "    " +
              self.finish(
                {
                  text: "def " +
                  field_names[i] +
                  "(self, value: " +
                  ty.render() +
                  ") -> None",
                  names: ["self", "value"],
                  ret: @map.PyNone,
                },
                setter,
                "        ",
              ),
            )
          } else {
            self.skipped = self.skipped + 1
          }
        }
      }
    }
    i = i + 1
  }
  let taken : Map[String, Bool] = Map([])
  for fname in field_names {
    taken.set(fname, true)
  }
  self.attach_methods(name, s.name, members, taken)
  let header = self.class_header(name, s.generics, [], false, true)
  Some(header + "\n" + body_of("MoonBit struct `" + s.name + "`.", members))
}

///|
fn Emitter::has_symbol(self : Emitter, symbol : String) -> Bool {
  match self.plan {
    Some(p) => p.has(symbol)
    None => false
  }
}

///|
/// The argument list a bound function sends, one expression per parameter.
///
/// Almost every value crosses as itself — a `list`, a `dict`, an `int` — but a
/// callable cannot: the guest holds an `Int32` id and asks the host to run it,
/// so the id has to be minted here, at the one place a Python function is in
/// hand.
fn Emitter::call_args(
  self : Emitter,
  symbol : String,
  names : Array[String],
) -> Array[String] {
  let wires = match self.plan {
    Some(p) =>
      match p.lookup(symbol) {
        Some(sym) => sym.params
        None => []
      }
    None => []
  }
  let out : Array[String] = []
  let mut i = 0
  for name in names {
    let wire = if i < wires.length() { Some(wires[i]) } else { None }
    match wire {
      Some(WCall(_, _)) =>
        out.push("_runtime.default().callback_id(" + name + ")")
      _ => out.push(name)
    }
    i = i + 1
  }
  out
}

///|
/// The handle-table tag for a type declared by this package, or 0 when the
/// guest never holds one.
fn Emitter::tag_of_type(self : Emitter, raw : String) -> Int32 {
  match self.plan {
    Some(p) => p.tag_of(@map.pkg_alias(self.pkg_name) + "." + raw)
    None => 0
  }
}

///|
/// The `moon_type_id` class attribute for a type this package declares, or
/// `None` when the guest holds no table for it.
///
/// Every class that can stand for a handle needs this — struct, enum, error and
/// opaque alike. A class that carries a handle but no tag can never be
/// released: `close()` would queue an id the guest cannot route to a table, and
/// the object would stay alive for the life of the process. Enums are the easy
/// one to forget, because they look like plain values, but `Json` is an enum
/// and `parse` returns a handle to one.
fn Emitter::tag_member(self : Emitter, raw : String) -> String? {
  if self.output == Stub {
    return None
  }
  let tag = self.tag_of_type(raw)
  if tag > 0 {
    Some("    moon_type_id = " + tag.to_string())
  } else {
    None
  }
}

///|
/// Every method defined on `<pkg>::<Type>`, with the package that declared it.
///
/// With a world this includes methods declared by other packages, which is how
/// `Json::stringify` (declared by the json package) ends up on the `Json` class
/// that the builtin stub emits.
fn Emitter::methods_for(
  self : Emitter,
  raw_name : String,
) -> Array[(String, @mbti.FuncDecl)] {
  match self.world {
    Some(w) =>
      match w.methods_on(self.pkg_name, raw_name) {
        Some(list) => list
        None => []
      }
    None =>
      match self.methods.get(raw_name) {
        Some(list) => list.map(fn(f) { (self.pkg_name, f) })
        None => []
      }
  }
}

///|
/// The naming context for a method: the declaring package's type table, with
/// its local names written through its own module when the method is being
/// rendered somewhere else.
fn Emitter::method_mapper(self : Emitter, decl_pkg : String) -> @map.Mapper {
  match self.world {
    Some(w) =>
      @map.Mapper::for_world(
        w,
        decl_pkg,
        if decl_pkg == self.pkg_name {
          None
        } else {
          Some(decl_pkg)
        },
      ).adopt_notes(self.mapper)
    None => self.mapper
  }
}

///|
fn Emitter::attach_methods(
  self : Emitter,
  class_name : String,
  raw_name : String,
  members : Array[String],
  taken : Map[String, Bool],
) -> Unit {
  for entry in self.methods_for(raw_name) {
    let decl_pkg = entry.0
    let f = entry.1
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
    match
      self.render_func(
        f,
        Some(class_name),
        Some(raw_name),
        decl_pkg,
        Some(name),
        self.method_mapper(decl_pkg),
      ) {
      Some(text) => members.push(text)
      None => self.skipped = self.skipped + 1
    }
  }
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
  if is_error && self.output == Bind {
    // The class is what a caller catches; the qualified MoonBit name is what
    // the guest puts in a failure frame. Registering the pair here is the only
    // place both are known at once.
    self.errors.push((raw_name, name))
  }
  let scoped = self.mapper.for_decl(generics, Some(name))
  let members : Array[String] = []
  match self.tag_member(raw_name) {
    Some(line) => members.push(line)
    None => ()
  }
  if self.output == Stub && ctors.length() == 1 && ctors[0].fields.length() > 0 {
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
  } else if self.output == Stub && (ctors.length() > 1 || is_error) {
    // Several payload shapes cannot be described by one signature; the tag
    // plus an open payload is the honest common denominator.
    self.typing_used.set("Any", true)
    members.push("    def __init__(self, tag: str, *args: Any) -> None: ...")
  }
  if self.output == Stub && ctors.length() > 0 {
    members.push("    @property")
    members.push("    def tag(self) -> str: ...")
  }
  let taken : Map[String, Bool] = Map([])
  if ctors.length() > 0 {
    taken.set("tag", true)
  }
  self.attach_methods(name, raw_name, members, taken)
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
    // A trait is a typing construct in both outputs: there is no guest object
    // to dispatch to.
    members.push(
      "    " +
      self.signature(
        mname,
        true,
        scoped,
        m.generics,
        drop_receiver(m.params),
        ret,
      ).text +
      ": ...",
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
  match self.tag_member(o.name) {
    Some(line) => members.push(line)
    None => ()
  }
  self.attach_methods(name, o.name, members, taken)
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
    self.typing_used.set("TypeAlias", true)
    let target = self.reexport_target(r.pkg, entry.name)
    match target {
      Some(rendered) => self.blocks.push(name + ": TypeAlias = " + rendered)
      None => {
        // The real class lives in a package this run did not include.
        self.typing_used.set("Any", true)
        self.blocks.push(name + ": TypeAlias = Any")
      }
    }
  }
}

///|
/// The Python name of a re-exported type, when its source package is known.
fn Emitter::reexport_target(
  self : Emitter,
  from : String,
  name : String,
) -> String? {
  match self.mapper.world {
    Some(w) =>
      match w.resolve_alias(self.pkg_name, from) {
        Some(pkg) =>
          match w.arity_of(pkg, name) {
            Some(_) =>
              Some(self.mapper.module_ref(pkg) + "." + @map.stub_name(name))
            None => None
          }
        None => None
      }
    None => None
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
  match self.output {
    Stub =>
      sb.write_string(
        "\"\"\"Type stubs for the MoonBit package `" +
        self.pkg_name +
        "`.\n\n" +
        "Generated by MoonBridge from `pkg.generated.mbti`. Do not edit by hand.\n" +
        "\"\"\"\n",
      )
    Bind =>
      sb.write_string(
        "\"\"\"Bindings that call into the MoonBit package `" +
        self.pkg_name +
        "`.\n\n" +
        "Generated by MoonBridge from `pkg.generated.mbti`. Do not edit by hand.\n\n" +
        "Every function here forwards to the guest as one frame; the signature is\n" +
        "the one the stub declares, so the type checker and the call agree by\n" +
        "construction. Fields and constructors are declared in the stub but not\n" +
        "bound here: reading a field and calling a constructor both need a symbol\n" +
        "the guest has to export, and a body that invented one would fail at the\n" +
        "call site instead of at generation time.\n" +
        "\"\"\"\n",
      )
  }
  if self.output == Bind {
    // Annotations must not be evaluated at definition time: a module may
    // reference a class from a module that is still importing us.
    sb.write_string("\nfrom __future__ import annotations\n")
  }
  let relative = self.mapper.imports()
  if self.output == Bind && relative.length() > 0 {
    // A sibling may only have a stub, and importing it eagerly would fail at
    // import time in a package the guest does not back. Annotations are
    // strings here, so the type checker needs the name and the interpreter
    // does not.
    self.typing_used.set("TYPE_CHECKING", true)
  }
  let typing_names : Array[String] = []
  for
    name in [
      "Any", "Callable", "Generic", "Optional", "Protocol", "Sequence", "TYPE_CHECKING",
      "TypeAlias",
    ] {
    if self.typing_used.contains(name) {
      typing_names.push(name)
    }
  }
  if self.typevars.length() > 0 {
    typing_names.push("TypeVar")
  }
  // `cast` is the one lowercase name in the list, so it sorts last.
  if self.typing_used.contains("cast") {
    typing_names.push("cast")
  }
  if typing_names.length() > 0 {
    sb.write_string("\nfrom typing import " + join(typing_names, ", ") + "\n")
  }
  // The module is executed inside the generated package, so the runtime it
  // calls is a sibling; the stub names the same file by its installed path,
  // because a stub is read outside any package context.
  if self.output == Bind {
    sb.write_string("\nfrom . import _runtime\n")
  }
  let relative = self.mapper.imports()
  if relative.length() > 0 {
    if self.output == Bind {
      sb.write_string("\nif TYPE_CHECKING:\n")
      for stem in relative {
        sb.write_string("    from . import " + stem + " as _" + stem + "\n")
      }
    } else {
      sb.write_string("\n")
      for stem in relative {
        // `_` plus the stem cannot collide with a generated class name, and one
        // alias per module keeps two packages' `Point` apart.
        sb.write_string("from . import " + stem + " as _" + stem + "\n")
      }
    }
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
  if runtime.length() > 0 && self.output == Stub {
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
  if self.output == Bind && self.errors.length() > 0 {
    // Sorted so that regenerating an unchanged package produces identical
    // bytes, and after the classes so every name exists when it runs.
    let lines : Array[String] = []
    for entry in self.errors {
      lines.push(
        "_runtime.register_failure(\"" +
        self.pkg_name +
        "::" +
        entry.0 +
        "\", " +
        entry.1 +
        ")\n",
      )
    }
    lines.sort()
    sb.write_string(
      "\n\n# A MoonBit `suberror` arrives as a name and a message; this is what turns\n" +
      "# the name back into the class a caller wrote `except` for.\n",
    )
    for line in lines {
      sb.write_string(line)
    }
  }
  sb.write_string("\n")
  sb.to_string()
}
