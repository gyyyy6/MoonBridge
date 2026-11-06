///|
/// Spike 01: prove the Python <-> MoonBit(Wasm) boundary.
///
/// ABI facts established here (this is what MoonBridge will build on):
///   * the `wasm` backend exports plain i32 functions via `#export_name`
///   * `String` / `Bytes` parameters arrive as a single i32 object pointer,
///     so the host must talk in *handles*, not C structs
///   * linear memory is exported through `options(link: ...)`, which lets the
///     host read/write the same bytes MoonBit sees

///|
/// Keeps host-visible buffers alive: without this the wasm side would free the
/// object as soon as the exporting function returns, and the host would hold a
/// dangling pointer. This is the seed of MoonBridge's real handle table.
let registry : Array[Bytes] = []

///|
/// Arithmetic: the trivial proof that the call ABI works.
#export_name("mb_add")
pub fn add(a : Int, b : Int) -> Int {
  a + b
}

///|
/// Non-trivial computation, to show the boundary is not limited to `+`.
#export_name("mb_fib")
pub fn fib(n : Int) -> Int {
  if n < 2 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

///|
/// Allocates host-writable memory owned by MoonBit and keeps it alive.
/// The host receives the object pointer as an i32 handle.
#export_name("mb_buf_new")
pub fn buf_new(n : Int) -> Bytes {
  let b = Bytes::from_array(Array::make(n, b'\x00'))
  registry.push(b)
  b
}

///|
/// Length of a MoonBit `Bytes`, so the host never has to guess the layout.
#export_name("mb_buf_len")
pub fn buf_len(b : Bytes) -> Int {
  b.length()
}

///|
/// Checksum over a MoonBit-owned buffer: proves the host can *write* bytes that
/// MoonBit then reads back.
#export_name("mb_buf_checksum")
pub fn buf_checksum(b : Bytes) -> Int {
  let mut sum = 0
  for i = 0; i < b.length(); i = i + 1 {
    sum = sum + b.unsafe_get(i).to_int()
  }
  sum
}

///|
/// Builds a MoonBit-owned buffer with a known fill value: proves MoonBit can
/// *write* bytes that the host then reads back out of exported memory.
#export_name("mb_buf_filled")
pub fn buf_filled(n : Int, value : Int) -> Bytes {
  let b = Bytes::from_array(Array::make(n, value.to_byte()))
  registry.push(b)
  b
}

///|
/// UTF-8 decode of a host-filled buffer. This is the "Python string -> MoonBit
/// String" direction in its raw form.
#export_name("mb_string_from_buf")
pub fn string_from_buf(b : Bytes) -> String {
  @utf8.decode_lossy(b[:])
}

///|
/// UTF-8 encode: the "MoonBit String -> Python bytes" direction.
#export_name("mb_string_to_buf")
pub fn string_to_buf(s : String) -> Bytes {
  let b = @utf8.encode(s)
  registry.push(b)
  b
}

///|
/// Counts code points, so the host can check that a multi-byte payload was
/// decoded correctly on the MoonBit side.
#export_name("mb_string_chars")
pub fn string_chars(s : String) -> Int {
  s.iter().count()
}

///|
/// A fingerprinted payload used by the host to locate the *data* offset inside
/// a MoonBit object without hard-coding compiler internals.
#export_name("mb_probe")
pub fn probe() -> Bytes {
  let b = @utf8.encode("MOONBRIDGE-PROBE-0123456789")
  registry.push(b)
  b
}
