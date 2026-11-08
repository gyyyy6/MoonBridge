//! The set of packages being generated, indexed for cross-package lookup.
//!
//! S2 generated one stub per package in isolation, so every `@other.Type` had
//! to degrade to `Any`. That was sound but expensive: `foreign` was the single
//! largest reason for lost precision on the corpus.
//!
//! Linking needs two facts that a single interface file does not carry:
//!
//! 1. **Which package an alias refers to.** `.mbti` prints qualified types with
//!    the short alias (`@json.Json`), never the full path, and the import block
//!    lists paths without aliases. The alias is the last path segment, which is
//!    unambiguous except when a package imports two paths with the same tail;
//!    those are recorded as ambiguous and left unresolved rather than guessed.
//!
//! 2. **Which package declares a receiver.** A method can be declared in a
//!    different package from the type it is defined on (MoonBit allows a
//!    package to attach methods to a type it does not own). So methods are
//!    indexed by the *receiver's* home package, and the stub for that package
//!    carries them.
//!
//! The world is a pure data structure: build it once from all parsed packages,
//! then every mapper is a cheap view onto it.

///|
/// The package that provides MoonBit's implicit prelude. An unqualified type
/// that a package neither declares nor re-exports can only come from here.
pub let builtin_pkg : String = "moonbitlang/core/builtin"

///|
/// What the linker knows about one package.
#derive(Debug)
pub(all) struct PkgInfo {
  /// Full package path, e.g. `moonbitlang/core/json`.
  name : String
  /// Python module stem, e.g. `moonbitlang__core__json`.
  stem : String
  /// Type name -> arity, for every type the package introduces. `-1` means the
  /// name was re-exported and its arity is not known.
  types : Map[String, Int32]
  /// Type names this package declares as `suberror`.
  ///
  /// A `Result[T, E]` can only be turned into a Python value when `E` can be
  /// turned into a message, and only an error type can: the guest writes
  /// `e.to_string()` on it. Holding the names here is what lets the planner say
  /// yes to `Result[Int, ParseError]` and no to `Result[Int, Int]` instead of
  /// emitting a call that does not compile.
  errors : Map[String, Bool]
  /// `@json` -> `moonbitlang/core/json`, from this package's import block.
  /// An empty value marks an alias that two imports claim.
  aliases : Map[String, String]
}

///|
#derive(Debug)
pub(all) struct World {
  pkgs : Map[String, PkgInfo]
  /// `<receiver package>::<Type>` -> the methods declared on it, each tagged
  /// with the package that declared it.
  methods : Map[String, Array[(String, @mbti.FuncDecl)]]
  /// `<package>::<Type>` for every `pub type X` declaration. A predefined type
  /// is opaque here, and MoonBit does not allow `Type::Type(...)` constructor
  /// calls on it; the planner needs to know that before emitting one.
  predefined : Map[String, Bool]
}

///|
/// The alias a package path is imported under: the last segment, prefixed with
/// `@`. `moonbitlang/core/json` is imported as `@json`, and the `.mbti` files
/// confirm this holds for hyphenated names too (`@crater-core`).
///
/// Public because the guest generator has to spell the same alias in the code
/// it emits; two spellings of one rule would drift.
pub fn pkg_alias(path : String) -> String {
  let parts = path.split("/").to_array()
  "@" + parts[parts.length() - 1].to_owned()
}

///|
/// Registers every type a package introduces, including re-exported names.
fn collect_types(pkg : @mbti.Package) -> Map[String, Int32] {
  let types : Map[String, Int32] = Map([])
  for decl in pkg.decls {
    match decl {
      @mbti.Struct(s) => types.set(s.name, s.generics.length())
      @mbti.Enum(e) => types.set(e.name, e.generics.length())
      @mbti.Error(e) => types.set(e.name, e.generics.length())
      @mbti.Opaque(o) => types.set(o.name, o.generics.length())
      @mbti.Alias(a) => types.set(a.name, a.generics.length())
      @mbti.Reexport(r) =>
        for entry in r.entries {
          if entry.kind == "type" {
            // A re-exported type may not be declared by the package that
            // re-exports it, so its arity is unknown here. Marking it `-1`
            // keeps the name usable bare and refuses to guess at `T[X]`.
            types.set(entry.as_name.unwrap_or(entry.name), -1)
          }
        }
      @mbti.Decl::Func(_)
      | @mbti.Value(_)
      | @mbti.Const(_)
      | @mbti.Trait(_)
      | @mbti.Impl(_) => ()
    }
  }
  types
}

///|
/// The `suberror` names a package declares.
fn collect_errors(pkg : @mbti.Package) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for decl in pkg.decls {
    match decl {
      @mbti.Error(e) => out.set(e.name, true)
      _ => ()
    }
  }
  out
}

///|
pub fn World::build(pkgs : Array[@mbti.Package]) -> World {
  let w : World = { pkgs: Map([]), methods: Map([]), predefined: Map([]), }
  // Pass one: identity and type tables. Every package must be registered
  // before any alias is resolved, because resolution is not order-dependent.
  for pkg in pkgs {
    for decl in pkg.decls {
      match decl {
        @mbti.Opaque(o) => w.predefined.set(pkg.name + "::" + o.name, true)
        _ => ()
      }
    }
    let aliases : Map[String, String] = Map([])
    for path in pkg.imports {
      let at = pkg_alias(path)
      match aliases.get(at) {
        // Two imports claim the same tail. Guessing one would silently point
        // annotations at the wrong package, so the alias becomes unresolved.
        Some(_) => aliases.set(at, "")
        None => aliases.set(at, path)
      }
    }
    w.pkgs.set(pkg.name, {
      name: pkg.name,
      stem: module_stem(pkg.name),
      types: collect_types(pkg),
      errors: collect_errors(pkg),
      aliases,
    })
  }
  // Pass two: methods, keyed by where the receiver lives rather than where the
  // method was written.
  for pkg in pkgs {
    for decl in pkg.decls {
      match decl {
        @mbti.Decl::Func(f) =>
          match f.receiver {
            Some(r) => {
              // A receiver that cannot be resolved at all still has to land
              // somewhere the stub generator will look for it, so an unknown
              // alias is treated as local. `home_of` returns `None` there; the
              // indexing below keeps the old, forgiving answer.
              let home = w.home_of(pkg.name, r).unwrap_or(pkg.name)
              let key = home + "::" + r.name
              let bucket = match w.methods.get(key) {
                Some(b) => b
                None => {
                  let b : Array[(String, @mbti.FuncDecl)] = []
                  w.methods.set(key, b)
                  b
                }
              }
              bucket.push((pkg.name, f))
            }
            None => ()
          }
        _ => ()
      }
    }
  }
  w
}

///|
/// Whether `q` names a `suberror` this world knows about.
///
/// Used by the planner for one decision only: a `Result[T, E]` can become a
/// Python value when `E` is an error type, because the guest can render it as a
/// message. Any other `E` has no `to_string` and the call would not compile.
pub fn World::is_suberror(self : World, pkg : String, q : @mbti.QName) -> Bool {
  let home = self.home_of(pkg, q).unwrap_or(pkg)
  match self.pkgs.get(home) {
    Some(info) => info.errors.contains(q.name)
    None => false
  }
}

///|
/// Whether `name` is declared as `pub type name` (a predefined/opaque type)
/// in `pkg`. Callers use it to avoid emitting constructor calls that MoonBit
/// rejects on anything that is not an enum.
pub fn World::is_predefined(self : World, pkg : String, name : String) -> Bool {
  self.predefined.get(pkg + "::" + name).unwrap_or(false)
}

///|
pub fn World::info_of(self : World, pkg : String) -> PkgInfo? {
  self.pkgs.get(pkg)
}

///|
/// The Python module stem of a package, when it is part of this world.
pub fn World::stem_of(self : World, pkg : String) -> String? {
  match self.pkgs.get(pkg) {
    Some(info) => Some(info.stem)
    None => None
  }
}

///|
/// Arity of a type declared by `pkg`, or `None` when the package is unknown or
/// does not introduce that name.
pub fn World::arity_of(self : World, pkg : String, name : String) -> Int32? {
  match self.pkgs.get(pkg) {
    Some(info) => info.types.get(name)
    None => None
  }
}

///|
/// Resolves an `@alias` in the context of one package.
pub fn World::resolve_alias(self : World, pkg : String, at : String) -> String? {
  if at == "@builtin" {
    return if self.pkgs.contains(builtin_pkg) {
      Some(builtin_pkg)
    } else {
      None
    }
  }
  match self.pkgs.get(pkg) {
    Some(info) =>
      match info.aliases.get(at) {
        Some(path) => if path == "" { None } else { Some(path) }
        None => None
      }
    None => None
  }
}

///|
/// The package a type name belongs to, as seen from `pkg`.
///
/// Resolution has three cases, and they are not the same question:
///
/// - `@alias.Name` names a package explicitly. An unknown alias is `None`
///   rather than a guess, because guessing points annotations at a package the
///   author did not write.
/// - A bare name the package declares is local.
/// - Any other bare name can only come from the implicit prelude.
///
/// The stub generator and the guest generator both ask this one function, so a
/// method can never land on a different class than the one the guest dispatches
/// to.
pub fn World::home_of(
  self : World,
  pkg : String,
  name : @mbti.QName,
) -> String? {
  match name.pkg {
    Some(at) => {
      if at == "@builtin" {
        return if self.pkgs.contains(builtin_pkg) {
          Some(builtin_pkg)
        } else {
          None
        }
      }
      self.resolve_alias(pkg, at)
    }
    None =>
      match self.pkgs.get(pkg) {
        Some(info) =>
          if info.types.contains(name.name) {
            Some(pkg)
          } else if self.pkgs.contains(builtin_pkg) {
            Some(builtin_pkg)
          } else {
            Some(pkg)
          }
        None => None
      }
  }
}

///|
/// Methods defined on `<pkg>::<Type>`, including those declared elsewhere.
pub fn World::methods_on(
  self : World,
  pkg : String,
  name : String,
) -> Array[(String, @mbti.FuncDecl)]? {
  self.methods.get(pkg + "::" + name)
}

///|
/// A one-line summary for the CLI and reports.
pub fn World::summary(self : World) -> String {
  let mut types = 0
  for name in self.pkgs.keys() {
    match self.pkgs.get(name) {
      Some(info) => types = types + info.types.length()
      None => ()
    }
  }
  let mut methods = 0
  for key in self.methods.keys() {
    match self.methods.get(key) {
      Some(list) => methods = methods + list.length()
      None => ()
    }
  }
  "packages=" +
  self.pkgs.length().to_string() +
  " types=" +
  types.to_string() +
  " methods=" +
  methods.to_string()
}
