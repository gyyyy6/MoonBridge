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
//!    different package from the type it is defined on: `Json::stringify` is
//!    declared by `moonbitlang/core/json` while `Json` itself lives in
//!    `moonbitlang/core/builtin`. So methods are indexed by the *receiver's*
//!    home package, and the stub for that package carries them.
//!
//! The world is a pure data structure: build it once from all parsed packages,
//! then every mapper is a cheap view onto it.

///|
/// The package that provides MoonBit's implicit prelude. An unqualified type
/// that a package neither declares nor re-exports can only come from here.
pub let builtin_pkg : String = "moonbitlang/core/builtin"

///|
/// What the linker knows about one package.
pub(all) struct PkgInfo {
  /// Full package path, e.g. `moonbitlang/core/json`.
  name : String
  /// Python module stem, e.g. `moonbitlang__core__json`.
  stem : String
  /// Type name -> arity, for every type the package introduces. `-1` means the
  /// name was re-exported and its arity is not known.
  types : Map[String, Int32]
  /// `@json` -> `moonbitlang/core/json`, from this package's import block.
  /// An empty value marks an alias that two imports claim.
  aliases : Map[String, String]
} derive(Debug)

///|
pub(all) struct World {
  pkgs : Map[String, PkgInfo]
  /// `<receiver package>::<Type>` -> the methods declared on it, each tagged
  /// with the package that declared it.
  methods : Map[String, Array[(String, @mbti.FuncDecl)]]
} derive(Debug)

///|
/// The alias a package path is imported under: the last segment, prefixed with
/// `@`. `moonbitlang/core/json` is imported as `@json`, and the `.mbti` files
/// confirm this holds for hyphenated names too (`@crater-core`).
fn alias_of(path : String) -> String {
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
pub fn World::build(pkgs : Array[@mbti.Package]) -> World {
  let w : World = { pkgs: Map([]), methods: Map([]), }
  // Pass one: identity and type tables. Every package must be registered
  // before any alias is resolved, because resolution is not order-dependent.
  for pkg in pkgs {
    let aliases : Map[String, String] = Map([])
    for path in pkg.imports {
      let at = alias_of(path)
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
      aliases,
    })
  }
  // Pass two: methods, keyed by where the receiver lives rather than where the
  // method was written.
  for pkg in pkgs {
    let info = w.info_of(pkg.name).unwrap()
    for decl in pkg.decls {
      match decl {
        @mbti.Decl::Func(f) =>
          match f.receiver {
            Some(r) => {
              let home = match r.pkg {
                Some(at) =>
                  match info.aliases.get(at) {
                    Some(path) => if path == "" { pkg.name } else { path }
                    None =>
                      if at == "@builtin" {
                        builtin_pkg
                      } else {
                        pkg.name
                      }
                  }
                // An unqualified receiver that the package does not declare
                // can only come from the implicit prelude.
                None =>
                  if info.types.contains(r.name) {
                    pkg.name
                  } else if w.pkgs.contains(builtin_pkg) {
                    builtin_pkg
                  } else {
                    pkg.name
                  }
              }
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
