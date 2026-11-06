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
