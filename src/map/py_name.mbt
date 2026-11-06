//! Python naming rules.
//!
//! MoonBit identifiers are close enough to Python that most names pass through
//! unchanged, but three classes of name break a generated stub and must be
//! rewritten deterministically:
//!
//! - **keywords** — a MoonBit function called `pass` or a type called `None`
//!   would produce a syntax error;
//! - **imports** — generated stubs import `Any`, `Optional`, `TypeAlias`, ...
//!   so a declaration reusing one of those names would shadow the import;
//! - **module names** — a package is `user/name/sub`, which is a filesystem
//!   path, not a Python module identifier.
//!
//! Every rewrite is a pure function of the input string, so generated output is
//! byte-stable across runs.

///|
/// Python 3 reserved words. Anything here cannot be a generated identifier.
pub fn is_python_keyword(name : String) -> Bool {
  match name {
    "False"
    | "None"
    | "True"
    | "and"
    | "as"
    | "assert"
    | "async"
    | "await"
    | "break"
    | "class"
    | "continue"
    | "def"
    | "del"
    | "elif"
    | "else"
    | "except"
    | "finally"
    | "for"
    | "from"
    | "global"
    | "if"
    | "import"
    | "in"
    | "is"
    | "lambda"
    | "nonlocal"
    | "not"
    | "or"
    | "pass"
    | "raise"
    | "return"
    | "try"
    | "while"
    | "with"
    | "yield" => true
    _ => false
  }
}

///|
/// Names the generated stub preamble binds. A declaration with one of these
/// names would shadow the binding, so it gets a trailing underscore.
pub fn is_stub_binding(name : String) -> Bool {
  match name {
    "Any"
    | "Generic"
    | "Optional"
    | "Protocol"
    | "Sequence"
    | "TypeAlias"
    | "TypeVar"
    | "MoonObject"
    | "MoonError" => true
    _ => false
  }
}

///|
/// Turns any string into a valid Python identifier.
///
/// ASCII letters, digits, `_` and non-ASCII code points are kept (Python 3
/// allows Unicode identifiers); everything else becomes `_`. A leading digit is
/// prefixed with `n_`, and a name that collides with a keyword or a stub
/// binding gets a trailing `_`.
pub fn python_identifier(raw : String) -> String {
  let sb = StringBuilder()
  for c in raw {
    let keep = c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '_' ||
      !c.is_ascii()
    if keep {
      sb.write_char(c)
    } else {
      sb.write_char('_')
    }
  }
  let mut out = sb.to_string()
  if out.length() == 0 {
    out = "_"
  }
  if out.to_array()[0].is_ascii_digit() {
    out = "n_" + out
  }
  if is_python_keyword(out) || is_stub_binding(out) {
    out = out + "_"
  }
  out
}

///|
/// Turns a package path into a Python module stem.
///
/// `moonbitlang/core/json` becomes `moonbitlang__core__json`. Path separators
/// become `__` and `-` becomes a single `_`, so the two separator styles that
/// real package names use stay distinguishable instead of collapsing into the
/// same stem. The mapping is still not injective for adversarial names (`a-b`
/// and `a_b` both yield `a_b`), so the generator keeps a stem registry and
/// refuses to overwrite an existing file instead of silently dropping a
/// package.
pub fn module_stem(pkg : String) -> String {
  let sb = StringBuilder()
  for c in pkg {
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      sb.write_char(c.to_ascii_lowercase())
    } else if c == '/' {
      sb.write_string("__")
    } else {
      sb.write_char('_')
    }
  }
  let mut out = sb.to_string()
  if out.length() == 0 {
    out = "pkg"
  }
  if out.to_array()[0].is_ascii_digit() {
    out = "n_" + out
  }
  out
}

///|
/// File name of a generated stub.
pub fn stub_filename(pkg : String) -> String {
  module_stem(pkg) + ".pyi"
}
