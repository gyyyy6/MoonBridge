//! Abstract syntax for `.mbti` interface files.
//!
//! The shape mirrors what `moon info` prints: a package header, an import list,
//! and a flat sequence of declarations. Nothing here depends on the binding
//! generator that consumes it, so the AST can be reused by any tool that needs
//! to read a MoonBit public API.

///|
/// How much of a declaration is visible outside its package.
pub(all) enum Access {
  /// `pub(all)`: constructors and fields are part of the public API.
  Open
  /// `pub(open)`: used for traits that downstream packages may implement.
  OpenTrait
  /// `pub`: the type is public, its constructors and fields are not.
  ReadOnly
  /// `priv`, or a plain `type` declaration with no visibility modifier.
  Private
} derive(Debug, Eq)

///|
/// A possibly package-qualified name: `Array`, `Self`, `@builtin.ToJson`.
pub(all) struct QName {
  /// `Some("@builtin")` when the source wrote `@builtin.ToJson`.
  pkg : String?
  name : String
} derive(Debug, Eq)

///|
pub fn QName::plain(name : String) -> QName {
  { pkg: None, name, }
}

///|
pub fn QName::qualified(pkg : String, name : String) -> QName {
  { pkg: Some(pkg), name, }
}

///|
pub fn QName::to_string(self : QName) -> String {
  match self.pkg {
    Some(p) => p + "." + self.name
    None => self.name
  }
}

///|
/// How a value parameter was written in a signature.
pub(all) enum ParamKind {
  /// `fn f(Int)` — positional.
  Positional
  /// `fn f(name? : Int)` — callable by name or positionally.
  Optional
  /// `fn f(name~ : Int)` — label only.
  Labeled
} derive(Debug, Eq)

///|
/// One parameter of a function type or declaration.
pub(all) struct Param {
  kind : ParamKind
  /// `None` for positional parameters.
  name : String?
  ty : TypeExpr
} derive(Debug, Eq)

///|
/// The effect annotation trailing a function type. MoonBit lets effects be
/// combined: `-> Unit noraise + nocancel` is legal, so this is a flag set
/// rather than a single tag.
pub(all) struct Effect {
  /// `raise` or `raise E`.
  raises : Bool
  /// `raise?`.
  raises_may : Bool
  /// `noraise`.
  no_raise : Bool
  /// `nocancel`.
  no_cancel : Bool
  /// The declared error type of `raise E`, when present.
  error : TypeExpr?
} derive(Debug, Eq)

///|
pub fn Effect::pure() -> Effect {
  {
    raises: false,
    raises_may: false,
    no_raise: false,
    no_cancel: false,
    error: None,
  }
}

///|
/// `true` when no effect annotation was written at all.
pub fn Effect::is_pure(self : Effect) -> Bool {
  !self.raises && !self.raises_may && !self.no_raise && !self.no_cancel
}

///|
/// A type as written in an interface: the only structural sharing is through
/// `Array[TypeExpr]`, so the tree is cheap to walk and easy to compare.
pub(all) enum TypeExpr {
  /// `Int`, `Array[Int]`, `@builtin.ToJson`.
  Named(QName, Array[TypeExpr])
  /// `Self[T]`.
  SelfType(Array[TypeExpr])
  /// `(Int, String)`.
  Tuple(Array[TypeExpr])
  /// `(T) -> Bool raise?`.
  Func(Array[Param], TypeExpr, Effect)
  /// `T?`.
  Optional(TypeExpr)
  /// `&Show` — a borrowed trait object, as in `inspect(&Show, ...)`.
  Borrowed(TypeExpr)
  /// `async (T) -> U` — an asynchronous function type.
  Async(TypeExpr)
  /// `Unit`.
  Unit
} derive(Debug, Eq)

///|
/// Appends every named type mentioned by `self` to `out`, including names
/// nested inside generic arguments, tuples, function types and `Self`.
pub fn TypeExpr::collect_names(self : TypeExpr, out : Array[QName]) -> Unit {
  match self {
    Named(q, args) => {
      out.push(q)
      args.each(fn(a) { a.collect_names(out) })
    }
    SelfType(args) => args.each(fn(a) { a.collect_names(out) })
    Tuple(items) => items.each(fn(a) { a.collect_names(out) })
    Func(params, ret, effect) => {
      params.each(fn(p) { p.ty.collect_names(out) })
      ret.collect_names(out)
      match effect.error {
        Some(e) => e.collect_names(out)
        None => ()
      }
    }
    Optional(inner) => inner.collect_names(out)
    Borrowed(inner) => inner.collect_names(out)
    Async(inner) => inner.collect_names(out)
    Unit => ()
  }
}

///|
/// The bare name of the type, ignoring generic arguments: useful for graph
/// nodes and for error messages.
pub fn TypeExpr::head_name(self : TypeExpr) -> String {
  match self {
    Named(q, _) => q.to_string()
    SelfType(_) => "Self"
    Tuple(_) => "Tuple"
    Func(_, _, _) => "Function"
    Optional(_) => "Option"
    Borrowed(_) => "Borrowed"
    Async(_) => "Async"
    Unit => "Unit"
  }
}

///|
/// A generic parameter with its trait bounds, e.g. `[T : Compare + Show]`.
pub(all) struct GenericParam {
  name : String
  bounds : Array[QName]
  /// `[T = Int]`.
  default : TypeExpr?
} derive(Debug, Eq)

///|
/// A `#attribute(...)` attached to a declaration. The arguments are kept as
/// raw text: nothing consuming the AST needs to interpret them yet, but they
/// must survive so the printer can reproduce the interface.
pub(all) struct Attr {
  name : String
  /// Raw argument text, without the enclosing parentheses.
  args : String
} derive(Debug, Eq)

///|
/// A `pub let` binding.
pub(all) struct ValueDecl {
  name : String
  ty : TypeExpr
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
/// A function declaration. Methods appear as `Type::method` and carry the
/// receiver in `receiver`.
pub(all) struct FuncDecl {
  name : String
  /// `pub async fn ...` — an asynchronous function.
  is_async : Bool
  receiver : QName?
  generics : Array[GenericParam]
  params : Array[Param]
  ret : TypeExpr
  effect : Effect
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
/// `pub const PI : Double = 0x3.243F...` — a compile-time constant. The value
/// is kept as raw text because it is a literal expression, not a type.
pub(all) struct ConstDecl {
  name : String
  ty : TypeExpr
  value : String
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
/// A struct field or enum constructor field.
///
/// Struct fields written positionally (`struct ArgsLoc(Int)`) have an empty
/// name. Constructor fields may additionally be labeled (`More(A, tail~ : List[A])`),
/// which `label` records.
pub(all) struct Field {
  /// Empty for a positional field.
  name : String
  ty : TypeExpr
  access : Access
  /// `mut tail : List[A]` and `mut val : T` both set this.
  is_mut : Bool
  /// `Some(Optional)` for `x? : T`, `Some(Labeled)` for `x~ : T`.
  label : ParamKind?
} derive(Debug, Eq)

///|
pub(all) struct StructDecl {
  name : String
  generics : Array[GenericParam]
  fields : Array[Field]
  /// `true` when the body was elided as `// private fields`.
  has_hidden_fields : Bool
  derives : Array[QName]
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
/// One enum constructor. `None`/`Some`-like constructors carry an empty field
/// list; payloads reuse `Field` so labeled constructor fields survive.
pub(all) struct Ctor {
  name : String
  fields : Array[Field]
} derive(Debug, Eq)

///|
pub(all) struct EnumDecl {
  name : String
  generics : Array[GenericParam]
  ctors : Array[Ctor]
  derives : Array[QName]
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
pub(all) struct TraitDecl {
  name : String
  generics : Array[GenericParam]
  /// Supertraits from `trait T : A + B`.
  supers : Array[QName]
  methods : Array[FuncDecl]
  attrs : Array[Attr]
  access : Access
} derive(Debug, Eq)

///|
pub(all) struct ImplDecl {
  trait_name : QName
  trait_args : Array[TypeExpr]
  for_ty : TypeExpr
  attrs : Array[Attr]
} derive(Debug, Eq)

///|
/// `typealias Name = Target`.
pub(all) struct AliasDecl {
  name : String
  generics : Array[GenericParam]
  target : TypeExpr
  access : Access
  attrs : Array[Attr]
} derive(Debug, Eq)

///|
/// An opaque `type Name` declaration: the type exists, its representation does
/// not.
pub(all) struct OpaqueDecl {
  name : String
  generics : Array[GenericParam]
  /// `type MatchResult derive(Eq)` — an opaque type can still derive traits.
  derives : Array[QName]
  access : Access
  attrs : Array[Attr]
} derive(Debug, Eq)

///|
/// One entry of a re-export block: `type ArrayView as View` or `trait ToJson`.
pub(all) struct ReexportEntry {
  /// `"type"` or `"trait"`.
  kind : String
  name : String
  /// The `as` alias, when the entry is renamed.
  as_name : String?
} derive(Debug, Eq)

///|
/// `pub using @pkg {type A as B, trait C}` — a re-export from another package.
pub(all) struct ReexportDecl {
  pkg : String
  entries : Array[ReexportEntry]
} derive(Debug, Eq)

///|
pub(all) enum Decl {
  Func(FuncDecl)
  Value(ValueDecl)
  Const(ConstDecl)
  Struct(StructDecl)
  Enum(EnumDecl)
  /// `suberror` — an enum that inhabits the error type.
  Error(EnumDecl)
  Trait(TraitDecl)
  Impl(ImplDecl)
  Alias(AliasDecl)
  Opaque(OpaqueDecl)
  Reexport(ReexportDecl)
} derive(Debug, Eq)

///|
/// Stable short name of a declaration kind, used by reports and counters.
pub fn Decl::kind_name(self : Decl) -> String {
  match self {
    Func(_) => "fn"
    Value(_) => "let"
    Const(_) => "const"
    Struct(_) => "struct"
    Enum(_) => "enum"
    Error(_) => "error"
    Trait(_) => "trait"
    Impl(_) => "impl"
    Alias(_) => "alias"
    Opaque(_) => "type"
    Reexport(_) => "using"
  }
}

///|
/// The name a declaration introduces, when it introduces one. `impl` and
/// `using` blocks introduce no local name.
pub fn Decl::declared_name(self : Decl) -> String? {
  match self {
    Func(f) => Some(f.name)
    Value(v) => Some(v.name)
    Const(c) => Some(c.name)
    Struct(s) => Some(s.name)
    Enum(e) => Some(e.name)
    Error(e) => Some(e.name)
    Trait(t) => Some(t.name)
    Impl(_) => None
    Alias(a) => Some(a.name)
    Opaque(o) => Some(o.name)
    Reexport(r) => {
      let first = r.entries[0]
      Some(first.as_name.unwrap_or(first.name))
    }
  }
}

///|
/// One parsed interface file.
pub(all) struct Package {
  name : String
  imports : Array[String]
  decls : Array[Decl]
} derive(Debug, Eq)

///|
/// Number of declarations of the given kind.
pub fn Package::count_kind(self : Package, kind : String) -> Int32 {
  self.decls.iter().filter(fn(d) { d.kind_name() == kind }).count()
}
