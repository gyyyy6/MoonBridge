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
/// The two buffers the host reads and writes. MoonBit has no mutable top-level
/// binding, so they live in a mutable record instead.
priv struct Buffers {
  /// Response buffer, reused across calls and grown only when a response does
  /// not fit, so the host can cache its pointer and refresh it on growth only.
  mut stage : Bytes
  /// Input buffer, owned by the guest so the host never has to know how a
  /// MoonBit `Bytes` object is laid out beyond one discovered offset.
  mut inbox : Bytes
}

///|
let buffers : Buffers = { stage: Bytes::new(256), inbox: Bytes::new(1024), }

///|
/// A fingerprinted buffer the host probes once at start-up to learn where the
/// data of a `Bytes` object lives. Held in a global so it is never collected
/// while the host might look at it.
let probe_bytes : Bytes = @utf8.encode("MOONBRIDGE-PROBE-DATA-OFFSET-0420")

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
pub fn stage_ptr() -> Bytes {
  buffers.stage
}

///|
#export_name("mb_probe")
pub fn probe() -> Bytes {
  probe_bytes
}

///|
#export_name("mb_live_handles")
pub fn live_handles() -> Int32 {
  handles.live_count()
}

///|
/// Copies `src` into the staging buffer, growing it if needed, and returns the
/// response length.
/// MoonBit's `Bytes` is immutable in this core release, so the staged response
/// is published by rebinding the handle rather than by copying into a fixed
/// buffer. The host therefore asks for the staging pointer after every call;
/// that second call is the price of not depending on a layout detail.
fn publish(src : Bytes) -> Int32 {
  buffers.stage = src
  src.length()
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
/// The dispatcher. Symbol names are `<package>::<declaration>`, so a host can
/// address any package in the guest without a registration step.
fn dispatch(symbol : String, payload : Bytes) -> @abi.Status {
  let args = @abi.decode(payload) catch {
    _ => return @abi.Failed("malformed argument frame")
  }
  let argv = match args {
    @abi.List(items) => items
    _ => [args]
  }
  if argv.length() == 0 {
    return @abi.Failed("no arguments")
  }
  match symbol {
    "json.parse" =>
      match argv[0].as_string() {
        Some(text) =>
          try {
            let doc = @json.parse(text[:])
            @abi.Ok(@abi.Handle(handles.insert(doc)))
          } catch {
            error => @abi.Failed(error.to_string())
          }
        None => @abi.Failed("json.parse expects a string")
      }
    "json.stringify" =>
      match argv[0].as_handle() {
        Some(id) =>
          match handles.get(id) {
            Some(doc) => @abi.Ok(@abi.Str(doc.stringify()))
            None => @abi.Failed("stale handle")
          }
        None => @abi.Failed("json.stringify expects a handle")
      }
    "json.valid" =>
      match argv[0].as_string() {
        Some(text) => @abi.Ok(@abi.Bool(@json.valid(text[:])))
        None => @abi.Failed("json.valid expects a string")
      }
    "abi.release" =>
      match argv[0].as_list() {
        Some(items) => {
          let mut released = 0
          for item in items {
            match item.as_int() {
              Some(id) => if handles.release(id) { released = released + 1 }
              None => ()
            }
          }
          @abi.Ok(@abi.Int(released))
        }
        None => @abi.Failed("abi.release expects a list of handle ids")
      }
    "abi.live" => @abi.Ok(@abi.Int(handles.live_count()))
    "bench.echo" =>
      // The floor of the protocol: decode one value, encode the same value.
      // Anything measured against this is the cost of real work, not of the
      // boundary.
      @abi.Ok(argv[0])
    "bench.sum" =>
      match argv[0].as_int() {
        Some(n) => @abi.Ok(@abi.Int(n * (n + 1) / 2))
        None => @abi.Failed("bench.sum expects an int")
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
