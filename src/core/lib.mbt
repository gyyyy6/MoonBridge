///|
/// MoonBridge core.
///
/// This package owns the *host ABI contract* shared by every generated binding.
/// Generated Python code and the generated MoonBit runtime both depend on the
/// constants below, so they live here instead of being duplicated per binding.
///
/// Design note: values never cross the boundary as raw pointers. The host holds
/// opaque `i32` handles that index a runtime-owned table; lifetime, ownership and
/// type identity all stay on the MoonBit side. See `docs/decisions/0001-wasm-first.md`.

///|
/// Version of the host ABI. Bumped whenever the handle protocol changes shape.
///
/// Generated packages embed the version they were built against and check it at
/// import time, so a stale wheel fails loudly instead of corrupting memory.
pub let abi_version : Int32 = 1

///|
/// Width of one handle slot in bytes. Handles are `i32` indices today; keeping
/// the width explicit leaves room for 64-bit handles on the native backend.
pub let handle_width : Int32 = 4

///|
/// Reserved handle value meaning "none". `0` is never a valid index, so `None`
/// can be encoded without a separate optional channel.
pub let handle_none : Int32 = 0

///|
/// Encodes a table index into the `i32` the host actually sees.
pub fn encode_handle(index : Int32) -> Int32 {
  if index < 0 {
    handle_none
  } else {
    index + 1
  }
}

///|
/// Decodes a host-provided `i32` back into a table index.
///
/// Returns `None` for the reserved value, which lets callers distinguish
/// "no object" from "invalid object" without panicking on bad input.
pub fn decode_handle(raw : Int32) -> Int32? {
  if raw == handle_none {
    None
  } else {
    Some(raw - 1)
  }
}
