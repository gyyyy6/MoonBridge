//! The value model that crosses the MoonBridge boundary.
//!
//! A MoonBit value is never copied into Python and a Python object never
//! becomes a MoonBit one. What crosses is a `Value`: a small, self-describing
//! tree of primitives, built by the guest from the real MoonBit value and by
//! the host from real Python objects. Anything that cannot be copied — a
//! struct with mutable state, an iterator, a closure — is sent as a `Handle`
//! instead, and stays where it was allocated.
//!
//! The set of variants is deliberately closed. Every addition is a wire-format
//! change that both the guest and the host have to learn, so the model carries
//! only what a binding actually needs:
//!
//! * primitives (`Bool`, `Int`, `Double`, `String`, `Bytes`)
//! * containers (`List`, `Map`)
//! * absence (`Null`)
//! * references to objects that stayed behind (`Handle`)
//!
//! There is no `Tagged` variant for enums: an enum with a payload is either
//! copied as a `Map` with a `tag` key or pinned behind a handle, and which one
//! is the generator's decision, not the protocol's.

///|
#derive(Debug, Eq)
pub(all) enum Value {
  Null
  Bool(Bool)
  Int(Int32)
  Double(Double)
  Str(String)
  Bytes(Bytes)
  List(Array[Value])
  /// Pairs rather than a hash map: keys are `Value`, which is not hashable
  /// when it contains a list, and order on the wire is cheap to keep.
  Map(Array[(Value, Value)])
  /// An object that stayed in the guest's heap, addressed by handle id.
  Handle(Int32)
}

///|
pub fn Value::unit() -> Value {
  Null
}

///|
pub fn Value::is_null(self : Value) -> Bool {
  match self {
    Null => true
    _ => false
  }
}

///|
/// The payload of a `Str`, or `None` when this is a different variant.
///
/// Conversion is total and explicit: a binding that receives the wrong shape
/// reports a protocol error instead of coercing, because coercion is where
/// bridges start losing data silently.
pub fn Value::as_string(self : Value) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
pub fn Value::as_int(self : Value) -> Int32? {
  match self {
    Int(i) => Some(i)
    _ => None
  }
}

///|
pub fn Value::as_double(self : Value) -> Double? {
  match self {
    Double(d) => Some(d)
    // An integer is exactly representable as a double, so widening is safe.
    Int(i) => Some(i.to_double())
    _ => None
  }
}

///|
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
pub fn Value::as_list(self : Value) -> Array[Value]? {
  match self {
    List(items) => Some(items)
    _ => None
  }
}

///|
pub fn Value::as_handle(self : Value) -> Int32? {
  match self {
    Handle(id) => Some(id)
    _ => None
  }
}

///|
/// A short name for diagnostics and for the tests that pin the wire format.
pub fn Value::tag(self : Value) -> String {
  match self {
    Null => "null"
    Bool(_) => "bool"
    Int(_) => "int"
    Double(_) => "double"
    Str(_) => "str"
    Bytes(_) => "bytes"
    List(_) => "list"
    Map(_) => "map"
    Handle(_) => "handle"
  }
}
