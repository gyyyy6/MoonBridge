//! A package that exists to be called across the boundary, and nothing else.
//!
//! The callback channel needs a MoonBit function that *calls* its function
//! value eagerly, and the standard library has none that a bridge can reach:
//! `debug_assert` compiles out of a release build, `Lexbuf::from_fn` stores its
//! argument for later, and the `Option`/`Result` helpers that would call one
//! take a generic `T` that has no wire shape.
//!
//! A channel that is only ever *established* is not tested. So this package is
//! four one-line functions whose whole body is the call, which makes the round
//! trip — Python callable, `Int32` id, wasm import, answer back through guest
//! memory — observable from a Python assertion.

///|
/// Calls a nullary callback.
pub fn call_int(f : () -> Int32) -> Int32 {
  f()
}

///|
/// Calls a callback with an argument, so the argument channel is exercised too.
pub fn call_with(f : (Int32) -> Int32, x : Int32) -> Int32 {
  f(x)
}

///|
/// Calls a callback that may produce nothing. `None` has to arrive as `None`
/// and not as a zero value, which is what makes this worth its own function.
pub fn call_opt(f : () -> String?) -> String {
  match f() {
    Some(s) => s
    None => "<none>"
  }
}

///|
/// Two callbacks in one frame, and the guest decides the order.
pub fn call_both(f : () -> Int32, g : (Int32) -> Int32, x : Int32) -> Int32 {
  g(f() + x)
}

///|
/// One mutable and one read-only field, so the generated setter/getter pair has
/// something to be tested against.
///
/// This lives here rather than in the standard library because the field-write
/// test needs a type whose mutability the bridge can rely on: `@lexbuf.StringScanner`
/// was mutable when this probe was written and is read-only as of moonc 0.10.22,
/// and no struct reachable from `json` / `builtin` / `lexbuf` exposes a `mut`
/// field any more. Regenerating after a core bump therefore cannot silently
/// take the write path out of the end-to-end coverage.
pub(all) struct Cursor {
  mut pos : Int32
  label : String
}
