//! A guest module: the MoonBit half of a generated binding.
//!
//! This is the piece the host talks to. It owns the buffers the host reads and
//! writes, decodes the call frame, dispatches to real MoonBit functions, and
//! encodes the answer. Everything here is plain MoonBit except the five
//! exported functions at the bottom, which are the entire ABI surface:
//!
//! ```text
//!   mb_in_reserve(n) -> ptr     grow the input buffer, return its object ptr
//!   mb_stage() -> ptr           the response buffer's object ptr
//!   mb_call(in_len) -> out_len  run the frame in the input buffer
//!   mb_live_handles() -> count  objects still held by the handle table
//!   mb_probe() -> ptr           a fingerprinted buffer, for layout discovery
//! ```
//!
//! The frame is `u32 le symbol length | symbol | payload`, all in the input
//! buffer. The response is a `@abi.Status` in the staging buffer.
//!
//! The dispatcher is written by hand for this demo module. S4 generates it from
//! the same type graph that produces the Python side, so the two halves of a
//! binding always describe the same surface.

///|
/// The response buffer, as a one-element array so the guest can replace it.
///
/// It is a `FixedArray[Byte]`, not a `Bytes`, and that is the whole point.
/// `Bytes` is immutable here, so publishing a response meant handing the host a
/// freshly encoded object, one per call. Every object a guest export returns
/// keeps a reference the host has no way to release, so each call left one
/// response behind: `bench/bench.py` measured 41 bytes of guest memory per call
/// growing without bound, with the handle table empty the whole time. A mutable
/// array can be written in place, so the host is handed the same object every
/// call and nothing accumulates.
let out_slot : Array[FixedArray[Byte]] = [FixedArray::make(4096, b'\x00')]

///|
/// The input buffer, owned by the guest so the host never has to know how a
/// MoonBit `Bytes` object is laid out beyond one discovered offset.
priv struct Buffers {
  /// Input buffer, grown on demand and kept for the session's lifetime.
  mut inbox : Bytes
}

///|
let buffers : Buffers = { inbox: Bytes::new(1024), }

///|
/// A fingerprinted buffer the host probes once at start-up to learn where the
/// data of a `Bytes` object lives. Held in a global so it is never collected
/// while the host might look at it.
let probe_bytes : Bytes = @utf8.encode("MOONBRIDGE-PROBE-DATA-OFFSET-0420")

///|
/// The same fingerprint as a `FixedArray[Byte]`. The two layouts are not
/// promised to be identical, so the host measures each one instead of assuming.
let probe_out : FixedArray[Byte] = {
  let marker = @utf8.encode("MOONBRIDGE-PROBE-DATA-OFFSET-0420")
  let arr : FixedArray[Byte] = FixedArray::make(marker.length(), b'\x00')
  arr.blit_from_bytesview(0, marker[:])
  arr
}

///|
/// Objects the host is holding. One table per concrete type, because MoonBit
/// has no runtime type information to downcast with.
let handles : @abi.HandleTable[Json] = @abi.HandleTable::new()

///|
/// Ensures the input buffer holds at least `n` bytes and returns it. The host
/// writes the frame into linear memory and passes only the length.
#export_name("mb_in_reserve")
pub fn in_reserve(n : Int32) -> Bytes {
  if buffers.inbox.length() < n {
    // Double rather than exact: a session that sends growing payloads should
    // not reallocate on every call.
    let size = if n * 2 > 1024 { n * 2 } else { 1024 }
    buffers.inbox = Bytes::new(size)
  }
  buffers.inbox
}

///|
#export_name("mb_stage")
pub fn stage_ptr() -> FixedArray[Byte] {
  out_slot[0]
}

///|
#export_name("mb_probe")
pub fn probe() -> Bytes {
  probe_bytes
}

///|
#export_name("mb_probe_out")
pub fn probe_out_ptr() -> FixedArray[Byte] {
  probe_out
}

///|
#export_name("mb_live_handles")
pub fn live_handles() -> Int32 {
  handles.live_count()
}

///|
/// Copies `src` into the response buffer, growing it if needed, and returns the
/// response length.
///
/// `Bytes` is immutable in this core release, so the response is copied into
/// the array the host already has a pointer to rather than handed over as a new
/// object. The copy is a `blit`, not a loop: the encoder writes into a `Bytes`,
/// the host reads out of the array, and both are the same bytes in linear
/// memory.
fn publish(src : Bytes) -> Int32 {
  let n = src.length()
  let cur = out_slot[0]
  if cur.length() < n {
    let mut size = cur.length()
    while size < n {
      size = size * 2
    }
    // A new array means a new address: the host refreshes its pointer when the
    // response no longer fits in the room it knows about.
    out_slot[0] = FixedArray::make(size, b'\x00')
  }
  out_slot[0].blit_from_bytesview(0, src[:])
  n
}

///|
fn read_u32(b : Bytes, at : Int32) -> Int32 {
  let mut v = 0
  for shift = 0; shift < 4; shift = shift + 1 {
    v = v | (b.unsafe_get(at + shift).to_int() << (shift * 8))
  }
  v
}

///|
fn slice(b : Bytes, start : Int32, end : Int32) -> Bytes {
  @buffer.from_bytes(b.exact_view(start~, end~)).to_bytes()
}

///|
/// `args[i]`, or `None` when the caller sent fewer arguments than the symbol
/// needs. A protocol error is a failure message, never an index panic.
fn arg(args : Array[@abi.Value], i : Int32) -> @abi.Value? {
  if i < args.length() {
    Some(args[i])
  } else {
    None
  }
}

///|
/// The dispatcher. Symbol names are `<package>::<declaration>`, with the
/// receiver type inserted for a method, so a host can address any package in
/// the guest without a registration step.
fn dispatch(symbol : String, payload : Bytes) -> @abi.Status {
  let args = @abi.decode(payload) catch {
    _ => return @abi.Failed("malformed argument frame")
  }
  let argv = match args {
    @abi.List(items) => items
    _ => [args]
  }
  match symbol {
    "moonbitlang/core/json::parse" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_string() {
            Some(text) =>
              try {
                let doc = @json.parse(text[:])
                @abi.Ok(@abi.Handle(handles.insert(doc)))
              } catch {
                error => @abi.Failed(error.to_string())
              }
            None => @abi.Failed("parse expects a string")
          }
        None => @abi.Failed("parse expects one argument")
      }
    "moonbitlang/core/json::Json::stringify" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_handle() {
            Some(id) =>
              match handles.get(id) {
                Some(doc) => @abi.Ok(@abi.Str(doc.stringify()))
                None => @abi.Failed("stale handle")
              }
            None => @abi.Failed("stringify expects a Json handle")
          }
        None => @abi.Failed("stringify expects one argument")
      }
    "moonbitlang/core/json::valid" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_string() {
            Some(text) => @abi.Ok(@abi.Bool(@json.valid(text[:])))
            None => @abi.Failed("valid expects a string")
          }
        None => @abi.Failed("valid expects one argument")
      }
    "abi.release" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_list() {
            Some(items) => {
              let mut released = 0
              for item in items {
                // A batch normally arrives as plain integers. A handle-tagged
                // id means the same thing, and refusing it would turn a
                // release into a silent no-op — the one failure mode a leak
                // test must never see.
                let id = match item.as_int() {
                  Some(n) => Some(n)
                  None => item.as_handle()
                }
                match id {
                  Some(id) => if handles.release(id) { released = released + 1 }
                  None => ()
                }
              }
              @abi.Ok(@abi.Int(released))
            }
            None => @abi.Failed("abi.release expects a list of handle ids")
          }
        None => @abi.Ok(@abi.Int(0))
      }
    "abi.live" => @abi.Ok(@abi.Int(handles.live_count()))
    "bench.echo" =>
      // The floor of the protocol: decode one value and encode it back.
      // Anything measured against this is the cost of real work, not of the
      // boundary.
      match arg(argv, 0) {
        Some(v) => @abi.Ok(v)
        None => @abi.Ok(@abi.Null)
      }
    "bench.sum" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_int() {
            Some(n) => @abi.Ok(@abi.Int(n * (n + 1) / 2))
            None => @abi.Failed("bench.sum expects an int")
          }
        None => @abi.Failed("bench.sum expects one argument")
      }
    _ => @abi.Failed("unknown symbol " + symbol)
  }
}

///|
/// Runs one frame. The host wrote `in_len` bytes into the input buffer first.
#export_name("mb_call")
pub fn call(in_len : Int32) -> Int32 {
  if in_len < 4 || in_len > buffers.inbox.length() {
    return publish(@abi.encode_status(@abi.Failed("bad frame length")))
  }
  let sym_len = read_u32(buffers.inbox, 0)
  if 4 + sym_len > in_len {
    return publish(@abi.encode_status(@abi.Failed("symbol overruns the frame")))
  }
  let symbol = @utf8.decode_lossy(
    slice(buffers.inbox, 4, 4 + sym_len).exact_view(),
  )
  let payload = slice(buffers.inbox, 4 + sym_len, in_len)
  publish(@abi.encode_status(dispatch(symbol, payload)))
}
