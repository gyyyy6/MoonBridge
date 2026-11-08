//! The MoonBit half of a generated MoonBridge binding. Do not edit.
//!
//! `moonbridge guest-gen` writes this file from the same type graph that
//! writes the Python module, so every branch below has a caller and every
//! symbol the Python side sends is matched here. Regenerate instead of
//! editing: a hand edit breaks that guarantee and nothing will say so.
//!
//! The ABI is six exports and two buffers:/n//!
//! ```text
//!   mb_in_reserve(n) -> ptr     grow the input buffer, return its object ptr
//!   mb_stage() -> ptr           the response buffer's object ptr
//!   mb_call(in_len) -> out_len  run the frame already in the input buffer
//!   mb_probe() -> ptr           a fingerprinted Bytes, for layout discovery
//!   mb_probe_out() -> ptr       the same fingerprint as a FixedArray
//!   mb_live_handles() -> count  objects the tables still hold
//! ```

///|
/// The response buffer, as a one-element array so the guest can replace it.
///
/// It is a `FixedArray[Byte]`, not a `Bytes`, and that is the whole point.
/// `Bytes` is immutable here, so publishing a response would mean handing the
/// host a freshly encoded object, one per call, and every object a guest
/// export returns keeps a reference the host cannot release. A mutable array
/// is written in place, so the host is handed the same object every call.
let out_slot : Array[FixedArray[Byte]] = [FixedArray::make(4096, b'\x00')]

///|
/// The input buffer, owned by the guest so the host never has to know how a
/// MoonBit `Bytes` is laid out beyond one discovered offset.
priv struct Buffers {
  mut inbox : Bytes
  /// Written by the host while a callback runs.
  mut cb_out : Bytes
}

///|
let buffers : Buffers = { inbox: Bytes::new(1024), cb_out: Bytes::new(256), }

///|
/// A fingerprinted buffer the host probes once to learn where the data of a
/// `Bytes` object lives.
let probe_bytes : Bytes = @utf8.encode("MOONBRIDGE-PROBE-DATA-OFFSET-0420")

///|
/// The same fingerprint as a `FixedArray[Byte]`. The two layouts are not
/// promised to match, so the host measures each one.
let probe_out : FixedArray[Byte] = {
  let marker = @utf8.encode("MOONBRIDGE-PROBE-DATA-OFFSET-0420")
  let arr : FixedArray[Byte] = FixedArray::make(marker.length(), b'\x00')
  arr.blit_from_bytesview(0, marker[:])
  arr
}

///|
/// One table per concrete type that crosses. MoonBit has no runtime type
/// information, so a value can only be stored where its type is known.
///
/// Vales are held behind a `Ref` rather than directly: a struct is a value,
/// so a handle that returned a copy could not be written through.
priv struct Tables {
  json_Json : @abi.HandleTable[@ref.Ref[@json.Json]]
  json_JsonDecodeError : @abi.HandleTable[@ref.Ref[@json.JsonDecodeError]]
  json_ParseError : @abi.HandleTable[@ref.Ref[@json.ParseError]]
  json_Replacer : @abi.HandleTable[@ref.Ref[@json.Replacer]]
  json_JsonPath : @abi.HandleTable[@ref.Ref[@json.JsonPath]]
  json_Position : @abi.HandleTable[@ref.Ref[@json.Position]]
  builtin_Failure : @abi.HandleTable[@ref.Ref[@builtin.Failure]]
  builtin_Int64 : @abi.HandleTable[@ref.Ref[@builtin.Int64]]
  builtin_UInt16 : @abi.HandleTable[@ref.Ref[@builtin.UInt16]]
  builtin_UInt64 : @abi.HandleTable[@ref.Ref[@builtin.UInt64]]
  builtin_Byte : @abi.HandleTable[@ref.Ref[@builtin.Byte]]
  builtin_Char : @abi.HandleTable[@ref.Ref[@builtin.Char]]
  builtin_Bytes : @abi.HandleTable[@ref.Ref[@builtin.Bytes]]
  builtin_V128 : @abi.HandleTable[@ref.Ref[@builtin.V128]]
  builtin_BytesView : @abi.HandleTable[@ref.Ref[@builtin.BytesView]]
  builtin_Error : @abi.HandleTable[@ref.Ref[@builtin.Error]]
  builtin_ArgsLoc : @abi.HandleTable[@ref.Ref[@builtin.ArgsLoc]]
  builtin_Hasher : @abi.HandleTable[@ref.Ref[@builtin.Hasher]]
  builtin_SourceLoc : @abi.HandleTable[@ref.Ref[@builtin.SourceLoc]]
  builtin_StringBuilder : @abi.HandleTable[@ref.Ref[@builtin.StringBuilder]]
  builtin_StringView : @abi.HandleTable[@ref.Ref[@builtin.StringView]]
  lexbuf_Lexbuf : @abi.HandleTable[@ref.Ref[@lexbuf.Lexbuf]]
  lexbuf_StringScanner : @abi.HandleTable[@ref.Ref[@lexbuf.StringScanner]]
}

///|
let tables : Tables = {
  json_Json: @abi.HandleTable::new(),
  json_JsonDecodeError: @abi.HandleTable::new(),
  json_ParseError: @abi.HandleTable::new(),
  json_Replacer: @abi.HandleTable::new(),
  json_JsonPath: @abi.HandleTable::new(),
  json_Position: @abi.HandleTable::new(),
  builtin_Failure: @abi.HandleTable::new(),
  builtin_Int64: @abi.HandleTable::new(),
  builtin_UInt16: @abi.HandleTable::new(),
  builtin_UInt64: @abi.HandleTable::new(),
  builtin_Byte: @abi.HandleTable::new(),
  builtin_Char: @abi.HandleTable::new(),
  builtin_Bytes: @abi.HandleTable::new(),
  builtin_V128: @abi.HandleTable::new(),
  builtin_BytesView: @abi.HandleTable::new(),
  builtin_Error: @abi.HandleTable::new(),
  builtin_ArgsLoc: @abi.HandleTable::new(),
  builtin_Hasher: @abi.HandleTable::new(),
  builtin_SourceLoc: @abi.HandleTable::new(),
  builtin_StringBuilder: @abi.HandleTable::new(),
  builtin_StringView: @abi.HandleTable::new(),
  lexbuf_Lexbuf: @abi.HandleTable::new(),
  lexbuf_StringScanner: @abi.HandleTable::new(),
}

///|
/// Ensures the input buffer holds at least `n` bytes and returns it.
#export_name("mb_in_reserve")
pub fn in_reserve(n : Int32) -> Bytes {
  if buffers.inbox.length() < n {
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
  live_total()
}

///|
/// Copies `src` into the response buffer, growing it if needed, and returns
/// the response length.
fn publish(src : Bytes) -> Int32 {
  let n = src.length()
  let cur = out_slot[0]
  if cur.length() < n {
    let mut size = cur.length()
    while size < n {
      size = size * 2
    }
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
/// Calls back into the host, which owns the callable. The request is already
/// in the response buffer; the answer is written to `buffers.cb_out`.
///
/// Only the wasm build has a host to call. The generator itself runs on
/// JavaScript, and it compiles this package too, so the other target gets a
/// stub: nothing can call a callback without a guest instance.
#cfg(target="wasm")
extern "wasm" fn mb_cb_invoke(cb_id : Int32, len : Int32) -> Int32 = "env" "mb_cb_invoke"

///|
#cfg(not(target="wasm"))
fn mb_cb_invoke(cb_id : Int32, len : Int32) -> Int32 {
  ignore(cb_id)
  ignore(len)
  0
}

///|
/// Hands the host a buffer to write a callback's result into, and returns it.
///
/// Exported because the host cannot allocate: it can only write into memory
/// the guest already owns, and it has to ask for that memory in the guest's
/// own allocator.
#export_name("mb_cb_buffer")
pub fn cb_buffer(n : Int32) -> Bytes {
  if n > buffers.cb_out.length() {
    let mut size = if buffers.cb_out.length() > 0 {
      buffers.cb_out.length()
    } else {
      256
    }
    while size < n {
      size = size * 2
    }
    buffers.cb_out = Bytes::new(size)
  }
  buffers.cb_out
}

///|
/// Runs one Python callable and returns its value.
///
/// `None` means the host could not produce a value — it raised, or the answer
/// did not decode. The caller substitutes a default and lets the host re-raise
/// the original exception once the outer call returns, so the bad value is
/// never observed.
fn invoke_callback(id : Int32, args : Array[@abi.Value]) -> @abi.Value? {
  let sent = publish(@abi.encode(@abi.Value::List(args)))
  let got = mb_cb_invoke(id, sent)
  if got <= 0 {
    return None
  }
  let frame = slice(buffers.cb_out, 0, got)
  let status = Some(@abi.decode_status(frame)) catch { _ => None }
  match status {
    Some(@abi.Ok(v)) => Some(v)
    _ => None
  }
}

///|
/// The raw id behind a handle argument, for a write that has to reach the
/// object rather than a copy of it.
fn arg_handle(args : Array[@abi.Value], i : Int32) -> Int32? {
  match arg(args, i) {
    Some(v) => v.as_handle()
    None => None
  }
}

///|
fn dec_str(v : @abi.Value?) -> String? {
  match v {
    Some(x) => x.as_string()
    None => None
  }
}

///|
fn dec_int(v : @abi.Value?) -> Int32? {
  match v {
    Some(x) => x.as_int()
    None => None
  }
}

///|
fn dec_bool(v : @abi.Value?) -> Bool? {
  match v {
    Some(x) => x.as_bool()
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.JsonDecodeError`.
fn dec_json_JsonDecodeError(v : @abi.Value?) -> @json.JsonDecodeError? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_JsonDecodeError.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.ParseError`.
fn dec_json_ParseError(v : @abi.Value?) -> @json.ParseError? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_ParseError.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_arr_json_Json(v : @abi.Value?) -> Array[@json.Json]? {
  match v {
    Some(@abi.List(items)) => {
      let out : Array[@json.Json] = []
      let mut ok = true
      for item in items {
        match dec_json_Json(Some(item)) {
          Some(x) => out.push(x)
          None => ok = false
        }
      }
      if ok {
        Some(out)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.Json`.
fn dec_json_Json(v : @abi.Value?) -> @json.Json? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_Json.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_double(v : @abi.Value?) -> Double? {
  match v {
    Some(x) =>
      match x.as_double() {
        Some(d) => Some(d)
        None =>
          match x.as_int() {
            Some(n) => Some(n.to_double())
            None => None
          }
      }
    None => None
  }
}

///|
fn dec_map_str_json_Json(v : @abi.Value?) -> Map[String, @json.Json]? {
  match v {
    Some(@abi.Map(pairs)) => {
      let out : Map[String, @json.Json] = Map([])
      let mut ok = true
      for pair in pairs {
        let (raw_key, raw_value) = pair
        match (dec_str(Some(raw_key)), dec_json_Json(Some(raw_value))) {
          (Some(kk), Some(vv)) => out.set(kk, vv)
          _ => ok = false
        }
      }
      if ok {
        Some(out)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.Replacer`.
fn dec_json_Replacer(v : @abi.Value?) -> @json.Replacer? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_Replacer.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.JsonPath`.
fn dec_json_JsonPath(v : @abi.Value?) -> @json.JsonPath? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_JsonPath.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@json.Position`.
fn dec_json_Position(v : @abi.Value?) -> @json.Position? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.json_Position.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_cb__to_bool(v : @abi.Value?) -> (() -> Bool)? {
  match v {
    Some(raw) =>
      match raw.as_int() {
        Some(id) =>
          Some(fn() {
            match invoke_callback(id, []) {
              Some(v) =>
                match dec_bool(Some(v)) {
                  Some(r) => r
                  None => false
                }
              None => false
            }
          })
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Failure`.
fn dec_builtin_Failure(v : @abi.Value?) -> @builtin.Failure? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Failure.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Byte`.
fn dec_builtin_Byte(v : @abi.Value?) -> @builtin.Byte? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Byte.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Char`.
fn dec_builtin_Char(v : @abi.Value?) -> @builtin.Char? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Char.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Int64`.
fn dec_builtin_Int64(v : @abi.Value?) -> @builtin.Int64? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Int64.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.UInt16`.
fn dec_builtin_UInt16(v : @abi.Value?) -> @builtin.UInt16? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_UInt16.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.UInt64`.
fn dec_builtin_UInt64(v : @abi.Value?) -> @builtin.UInt64? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_UInt64.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_arr_builtin_Char(v : @abi.Value?) -> Array[@builtin.Char]? {
  match v {
    Some(@abi.List(items)) => {
      let out : Array[@builtin.Char] = []
      let mut ok = true
      for item in items {
        match dec_builtin_Char(Some(item)) {
          Some(x) => out.push(x)
          None => ok = false
        }
      }
      if ok {
        Some(out)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.V128`.
fn dec_builtin_V128(v : @abi.Value?) -> @builtin.V128? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_V128.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Bytes`.
fn dec_builtin_Bytes(v : @abi.Value?) -> @builtin.Bytes? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Bytes.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.BytesView`.
fn dec_builtin_BytesView(v : @abi.Value?) -> @builtin.BytesView? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_BytesView.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_arr_builtin_Byte(v : @abi.Value?) -> Array[@builtin.Byte]? {
  match v {
    Some(@abi.List(items)) => {
      let out : Array[@builtin.Byte] = []
      let mut ok = true
      for item in items {
        match dec_builtin_Byte(Some(item)) {
          Some(x) => out.push(x)
          None => ok = false
        }
      }
      if ok {
        Some(out)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Error`.
fn dec_builtin_Error(v : @abi.Value?) -> @builtin.Error? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Error.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.ArgsLoc`.
fn dec_builtin_ArgsLoc(v : @abi.Value?) -> @builtin.ArgsLoc? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_ArgsLoc.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.Hasher`.
fn dec_builtin_Hasher(v : @abi.Value?) -> @builtin.Hasher? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Hasher.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.SourceLoc`.
fn dec_builtin_SourceLoc(v : @abi.Value?) -> @builtin.SourceLoc? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_SourceLoc.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.StringBuilder`.
fn dec_builtin_StringBuilder(v : @abi.Value?) -> @builtin.StringBuilder? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_StringBuilder.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@builtin.StringView`.
fn dec_builtin_StringView(v : @abi.Value?) -> @builtin.StringView? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_StringView.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_cb__to_opt_str(v : @abi.Value?) -> (() -> String?)? {
  match v {
    Some(raw) =>
      match raw.as_int() {
        Some(id) =>
          Some(fn() {
            match invoke_callback(id, []) {
              Some(v) => dec_str(Some(v))
              None => None
            }
          })
        None => None
      }
    None => None
  }
}

///|
/// A handle from the host, resolved against the table for `@lexbuf.StringScanner`.
fn dec_lexbuf_StringScanner(v : @abi.Value?) -> @lexbuf.StringScanner? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.lexbuf_StringScanner.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn dec_cb__to_int(v : @abi.Value?) -> (() -> Int32)? {
  match v {
    Some(raw) =>
      match raw.as_int() {
        Some(id) =>
          Some(fn() {
            match invoke_callback(id, []) {
              Some(v) =>
                match dec_int(Some(v)) {
                  Some(r) => r
                  None => 0
                }
              None => 0
            }
          })
        None => None
      }
    None => None
  }
}

///|
fn dec_cb_int_to_int(v : @abi.Value?) -> ((Int32) -> Int32)? {
  match v {
    Some(raw) =>
      match raw.as_int() {
        Some(id) =>
          Some(fn(a0) {
            match invoke_callback(id, [enc_int(Some(a0))]) {
              Some(v) =>
                match dec_int(Some(v)) {
                  Some(r) => r
                  None => 0
                }
              None => 0
            }
          })
        None => None
      }
    None => None
  }
}

///|
fn enc_json_Json(v : @json.Json?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.json_Json.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_bool(v : Bool?) -> @abi.Value {
  match v {
    Some(x) => @abi.Bool(x)
    None => @abi.Value::unit()
  }
}

///|
fn enc_str(v : String?) -> @abi.Value {
  match v {
    Some(x) => @abi.Str(x)
    None => @abi.Value::unit()
  }
}

///|
fn enc_json_JsonPath(v : @json.JsonPath?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.json_JsonPath.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_json_Position(v : @json.Position?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.json_Position.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_int(v : Int32?) -> @abi.Value {
  match v {
    Some(x) => @abi.Int(x)
    None => @abi.Value::unit()
  }
}

///|
fn enc_unit(_v : Unit?) -> @abi.Value {
  @abi.Value::unit()
}

///|
fn enc_builtin_Int64(v : @builtin.Int64?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Int64.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_UInt16(v : @builtin.UInt16?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_UInt16.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_UInt64(v : @builtin.UInt64?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_UInt64.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_Byte(v : @builtin.Byte?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Byte.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_Char(v : @builtin.Char?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Char.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_double(v : Double?) -> @abi.Value {
  match v {
    Some(x) => @abi.Double(x)
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_Bytes(v : @builtin.Bytes?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Bytes.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_strview(v : StringView?) -> @abi.Value {
  match v {
    Some(x) => @abi.Str(x.to_owned())
    None => @abi.Value::unit()
  }
}

///|
fn enc_arr_builtin_Char(v : Array[@builtin.Char]?) -> @abi.Value raise {
  match v {
    Some(items) => {
      let out : Array[@abi.Value] = []
      for item in items {
        out.push(enc_builtin_Char(Some(item)))
      }
      @abi.List(out)
    }
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_BytesView(v : @builtin.BytesView?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_BytesView.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_arr_builtin_Byte(v : Array[@builtin.Byte]?) -> @abi.Value raise {
  match v {
    Some(items) => {
      let out : Array[@abi.Value] = []
      for item in items {
        out.push(enc_builtin_Byte(Some(item)))
      }
      @abi.List(out)
    }
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_StringView(v : @builtin.StringView?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_StringView.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_lexbuf_Lexbuf(v : @lexbuf.Lexbuf?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.lexbuf_Lexbuf.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_lexbuf_StringScanner(v : @lexbuf.StringScanner?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.lexbuf_StringScanner.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
/// Objects the tables still hold.
fn live_total() -> Int32 {
  tables.json_Json.live_count() +
  tables.json_JsonDecodeError.live_count() +
  tables.json_ParseError.live_count() +
  tables.json_Replacer.live_count() +
  tables.json_JsonPath.live_count() +
  tables.json_Position.live_count() +
  tables.builtin_Failure.live_count() +
  tables.builtin_Int64.live_count() +
  tables.builtin_UInt16.live_count() +
  tables.builtin_UInt64.live_count() +
  tables.builtin_Byte.live_count() +
  tables.builtin_Char.live_count() +
  tables.builtin_Bytes.live_count() +
  tables.builtin_V128.live_count() +
  tables.builtin_BytesView.live_count() +
  tables.builtin_Error.live_count() +
  tables.builtin_ArgsLoc.live_count() +
  tables.builtin_Hasher.live_count() +
  tables.builtin_SourceLoc.live_count() +
  tables.builtin_StringBuilder.live_count() +
  tables.builtin_StringView.live_count() +
  tables.lexbuf_Lexbuf.live_count() +
  tables.lexbuf_StringScanner.live_count()
}

///|
/// Releases one id from the table its tag names. The tag exists because an id
/// is only unique within one table.
fn release_tag(tag : Int32, id : Int32) -> Bool {
  match tag {
    1 => tables.json_Json.release(id)
    2 => tables.json_JsonDecodeError.release(id)
    3 => tables.json_ParseError.release(id)
    4 => tables.json_Replacer.release(id)
    5 => tables.json_JsonPath.release(id)
    6 => tables.json_Position.release(id)
    7 => tables.builtin_Failure.release(id)
    8 => tables.builtin_Int64.release(id)
    9 => tables.builtin_UInt16.release(id)
    10 => tables.builtin_UInt64.release(id)
    11 => tables.builtin_Byte.release(id)
    12 => tables.builtin_Char.release(id)
    13 => tables.builtin_Bytes.release(id)
    14 => tables.builtin_V128.release(id)
    15 => tables.builtin_BytesView.release(id)
    16 => tables.builtin_Error.release(id)
    17 => tables.builtin_ArgsLoc.release(id)
    18 => tables.builtin_Hasher.release(id)
    19 => tables.builtin_SourceLoc.release(id)
    20 => tables.builtin_StringBuilder.release(id)
    21 => tables.builtin_StringView.release(id)
    22 => tables.lexbuf_Lexbuf.release(id)
    23 => tables.lexbuf_StringScanner.release(id)
    _ => false
  }
}

///|
fn release_pairs(items : Array[@abi.Value]) -> @abi.Status {
  let mut released = 0
  for item in items {
    let pair = match item.as_list() {
      Some(p) => p
      None => return @abi.Failed("abi.release wants [tag, id] pairs")
    }
    if pair.length() != 2 {
      return @abi.Failed("abi.release wants [tag, id] pairs")
    }
    let tag = match pair[0].as_int() {
      Some(n) => n
      None => return @abi.Failed("abi.release: the tag must be an int")
    }
    let id = match pair[1].as_int() {
      Some(n) => n
      None => return @abi.Failed("abi.release: the id must be an int")
    }
    if release_tag(tag, id) {
      released = released + 1
    }
  }
  @abi.Ok(@abi.Int(released))
}

///|
/// The dispatcher. A symbol is
/// `<declaring package>::<function>` or
/// `<declaring package>::<Type>::<name>`, which is what the generated Python
/// module sends.
fn dispatch(symbol : String, payload : Bytes) -> @abi.Status {
  let args = @abi.decode(payload) catch {
    _ => return @abi.Failed("malformed argument frame")
  }
  let argv = match args {
    @abi.List(items) => items
    _ => [args]
  }
  match symbol {
    "moonbitlang/core/json::parse" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed("moonbitlang/core/json::parse: bad argument 1")
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_bool(arg(argv, 2))
      let a3 = dec_bool(arg(argv, 3))
      let value = try {
        match a1 {
          Some(v1) =>
            match a2 {
              Some(v2) =>
                match a3 {
                  Some(v3) =>
                    @json.parse(
                      a0[:],
                      max_nesting_depth=v1,
                      reject_duplicate_keys=v2,
                      preserve_number_repr=v3,
                    )
                  None =>
                    @json.parse(
                      a0[:],
                      max_nesting_depth=v1,
                      reject_duplicate_keys=v2,
                    )
                }
              None =>
                match a3 {
                  Some(v3) =>
                    @json.parse(
                      a0[:],
                      max_nesting_depth=v1,
                      preserve_number_repr=v3,
                    )
                  None => @json.parse(a0[:], max_nesting_depth=v1)
                }
            }
          None =>
            match a2 {
              Some(v2) =>
                match a3 {
                  Some(v3) =>
                    @json.parse(
                      a0[:],
                      reject_duplicate_keys=v2,
                      preserve_number_repr=v3,
                    )
                  None => @json.parse(a0[:], reject_duplicate_keys=v2)
                }
              None =>
                match a3 {
                  Some(v3) => @json.parse(a0[:], preserve_number_repr=v3)
                  None => @json.parse(a0[:])
                }
            }
        }
      } catch {
        error =>
          return @abi.FailedAs(
            "moonbitlang/core/json::ParseError",
            error.to_string(),
          )
      }
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::valid" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed("moonbitlang/core/json::valid: bad argument 1")
      }
      let value = @json.valid(a0[:])
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/json::JsonDecodeError::equal" => {
      let a0 = match dec_json_JsonDecodeError(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonDecodeError::equal: bad argument 1",
          )
      }
      let a1 = match dec_json_JsonDecodeError(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonDecodeError::equal: bad argument 2",
          )
      }
      let value = @json.JsonDecodeError::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/json::JsonDecodeError::to_string" => {
      let a0 = match dec_json_JsonDecodeError(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonDecodeError::to_string: bad argument 1",
          )
      }
      let value = @json.JsonDecodeError::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/json::ParseError::equal" => {
      let a0 = match dec_json_ParseError(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::ParseError::equal: bad argument 1",
          )
      }
      let a1 = match dec_json_ParseError(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::ParseError::equal: bad argument 2",
          )
      }
      let value = @json.ParseError::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/json::ParseError::to_string" => {
      let a0 = match dec_json_ParseError(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::ParseError::to_string: bad argument 1",
          )
      }
      let value = @json.ParseError::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/json::Json::array" => {
      let a0 = match dec_arr_json_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::array: bad argument 1",
          )
      }
      let value = @json.Json::array(a0)
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::boolean" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::boolean: bad argument 1",
          )
      }
      let value = @json.Json::boolean(a0)
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::empty_object" => {
      let value = @json.Json::empty_object()
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::equal" => {
      let a0 = match dec_json_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::equal: bad argument 1",
          )
      }
      let a1 = match dec_json_Json(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::equal: bad argument 2",
          )
      }
      let value = @json.Json::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/json::Json::null" => {
      let value = @json.Json::null()
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::number" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::number: bad argument 1",
          )
      }
      let a1 = dec_str(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @json.Json::number(a0, repr=v1)
        None => @json.Json::number(a0)
      }
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::object" => {
      let a0 = match dec_map_str_json_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::object: bad argument 1",
          )
      }
      let value = @json.Json::object(a0)
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::string" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::string: bad argument 1",
          )
      }
      let value = @json.Json::string(a0)
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Json::stringify" => {
      let a0 = match dec_json_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::stringify: bad argument 1",
          )
      }
      let a1 = dec_bool(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let a3 = dec_json_Replacer(arg(argv, 3))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) =>
              match a3 {
                Some(v3) =>
                  @json.Json::stringify(
                    a0,
                    escape_slash=v1,
                    indent=v2,
                    replacer=v3,
                  )
                None => @json.Json::stringify(a0, escape_slash=v1, indent=v2)
              }
            None =>
              match a3 {
                Some(v3) =>
                  @json.Json::stringify(a0, escape_slash=v1, replacer=v3)
                None => @json.Json::stringify(a0, escape_slash=v1)
              }
          }
        None =>
          match a2 {
            Some(v2) =>
              match a3 {
                Some(v3) => @json.Json::stringify(a0, indent=v2, replacer=v3)
                None => @json.Json::stringify(a0, indent=v2)
              }
            None =>
              match a3 {
                Some(v3) => @json.Json::stringify(a0, replacer=v3)
                None => @json.Json::stringify(a0)
              }
          }
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/json::Json::transform" => {
      let a0 = match dec_json_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::transform: bad argument 1",
          )
      }
      let a1 = match dec_json_Replacer(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Json::transform: bad argument 2",
          )
      }
      let value = @json.Json::transform(a0, a1)
      @abi.Ok(enc_json_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::JsonPath::add_index" => {
      let a0 = match dec_json_JsonPath(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::add_index: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::add_index: bad argument 2",
          )
      }
      let value = @json.JsonPath::add_index(a0, a1)
      @abi.Ok(enc_json_JsonPath(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::JsonPath::add_key" => {
      let a0 = match dec_json_JsonPath(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::add_key: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::add_key: bad argument 2",
          )
      }
      let value = @json.JsonPath::add_key(a0, a1)
      @abi.Ok(enc_json_JsonPath(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::JsonPath::equal" => {
      let a0 = match dec_json_JsonPath(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::equal: bad argument 1",
          )
      }
      let a1 = match dec_json_JsonPath(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::equal: bad argument 2",
          )
      }
      let value = @json.JsonPath::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/json::JsonPath::to_string" => {
      let a0 = match dec_json_JsonPath(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::JsonPath::to_string: bad argument 1",
          )
      }
      let value = @json.JsonPath::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/json::Position::__new__" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::__new__: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::__new__: bad argument 2",
          )
      }
      let value = @json.Position::{ line: a0, column: a1, }
      @abi.Ok(enc_json_Position(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/json::Position::__get_line" => {
      let a0 = match dec_json_Position(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::__get_line: bad argument 1",
          )
      }
      let value = a0.line
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/json::Position::__get_column" => {
      let a0 = match dec_json_Position(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::__get_column: bad argument 1",
          )
      }
      let value = a0.column
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/json::Position::equal" => {
      let a0 = match dec_json_Position(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::equal: bad argument 1",
          )
      }
      let a1 = match dec_json_Position(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/json::Position::equal: bad argument 2",
          )
      }
      let value = @json.Position::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::debug_assert" => {
      let a0 = match dec_cb__to_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::debug_assert: bad argument 1",
          )
      }
      let value = @builtin.debug_assert(a0)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Failure::to_string" => {
      let a0 = match dec_builtin_Failure(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Failure::to_string: bad argument 1",
          )
      }
      let value = @builtin.Failure::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Unit::compare" => {
      let value = @builtin.Unit::compare((), ())
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Unit::equal" => {
      let value = @builtin.Unit::equal((), ())
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Unit::hash" => {
      let value = @builtin.Unit::hash(())
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Unit::to_string" => {
      let value = @builtin.Unit::to_string(())
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::compare" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::compare: bad argument 1",
          )
      }
      let a1 = match dec_bool(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::compare: bad argument 2",
          )
      }
      let value = @builtin.Bool::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::equal" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::equal: bad argument 1",
          )
      }
      let a1 = match dec_bool(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::equal: bad argument 2",
          )
      }
      let value = @builtin.Bool::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::hash" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::hash: bad argument 1",
          )
      }
      let value = @builtin.Bool::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::to_int" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::to_int: bad argument 1",
          )
      }
      let value = @builtin.Bool::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::to_int64" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::to_int64: bad argument 1",
          )
      }
      let value = @builtin.Bool::to_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bool::to_string" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::to_string: bad argument 1",
          )
      }
      let value = @builtin.Bool::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Bool::to_uint16" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::to_uint16: bad argument 1",
          )
      }
      let value = @builtin.Bool::to_uint16(a0)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bool::to_uint64" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bool::to_uint64: bad argument 1",
          )
      }
      let value = @builtin.Bool::to_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::add" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::add: bad argument 2",
          )
      }
      let value = @builtin.Byte::add(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::compare" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::compare: bad argument 2",
          )
      }
      let value = @builtin.Byte::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::default" => {
      let value = @builtin.Byte::default()
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::div" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::div: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::div: bad argument 2",
          )
      }
      let value = @builtin.Byte::div(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::equal" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::equal: bad argument 2",
          )
      }
      let value = @builtin.Byte::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::hash" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::hash: bad argument 1",
          )
      }
      let value = @builtin.Byte::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::land" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::land: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::land: bad argument 2",
          )
      }
      let value = @builtin.Byte::land(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::lnot" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::lnot: bad argument 1",
          )
      }
      let value = @builtin.Byte::lnot(a0)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::lor" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::lor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::lor: bad argument 2",
          )
      }
      let value = @builtin.Byte::lor(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::lxor" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::lxor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::lxor: bad argument 2",
          )
      }
      let value = @builtin.Byte::lxor(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::mod" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::mod: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::mod: bad argument 2",
          )
      }
      let value = @builtin.Byte::mod(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::mul" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::mul: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::mul: bad argument 2",
          )
      }
      let value = @builtin.Byte::mul(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::popcnt" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::popcnt: bad argument 1",
          )
      }
      let value = @builtin.Byte::popcnt(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::shl" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::shl: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::shl: bad argument 2",
          )
      }
      let value = @builtin.Byte::shl(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::shr" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::shr: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::shr: bad argument 2",
          )
      }
      let value = @builtin.Byte::shr(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::sub" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::sub: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::sub: bad argument 2",
          )
      }
      let value = @builtin.Byte::sub(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::to_char" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_char: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_char(a0)
      @abi.Ok(enc_builtin_Char(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::to_double" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_double: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_double(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::to_hex" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_hex: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_hex(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::to_int" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_int: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::to_int64" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_int64: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::to_string" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_string: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Byte::to_uint16" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_uint16: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_uint16(a0)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Byte::to_uint64" => {
      let a0 = match dec_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Byte::to_uint64: bad argument 1",
          )
      }
      let value = @builtin.Byte::to_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Char::compare" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::compare: bad argument 2",
          )
      }
      let value = @builtin.Char::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Char::equal" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::equal: bad argument 2",
          )
      }
      let value = @builtin.Char::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::escape" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::escape: bad argument 1",
          )
      }
      let a1 = dec_bool(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.Char::escape(a0, quote=v1)
        None => @builtin.Char::escape(a0)
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Char::hash" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::hash: bad argument 1",
          )
      }
      let value = @builtin.Char::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_alphabetic" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_alphabetic: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_alphabetic(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_control" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_control: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_control(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_digit" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_digit: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_digit(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_graphic" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_graphic: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_graphic(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_hexdigit" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_hexdigit: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_hexdigit(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_lowercase" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_lowercase: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_lowercase(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_octdigit" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_octdigit: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_octdigit(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_punctuation" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_punctuation: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_punctuation(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_uppercase" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_uppercase: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_uppercase(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_ascii_whitespace" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_ascii_whitespace: bad argument 1",
          )
      }
      let value = @builtin.Char::is_ascii_whitespace(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_bmp" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_bmp: bad argument 1",
          )
      }
      let value = @builtin.Char::is_bmp(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_control" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_control: bad argument 1",
          )
      }
      let value = @builtin.Char::is_control(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_numeric" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_numeric: bad argument 1",
          )
      }
      let value = @builtin.Char::is_numeric(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_printable" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_printable: bad argument 1",
          )
      }
      let value = @builtin.Char::is_printable(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::is_whitespace" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::is_whitespace: bad argument 1",
          )
      }
      let value = @builtin.Char::is_whitespace(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Char::to_ascii_lowercase" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::to_ascii_lowercase: bad argument 1",
          )
      }
      let value = @builtin.Char::to_ascii_lowercase(a0)
      @abi.Ok(enc_builtin_Char(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Char::to_ascii_uppercase" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::to_ascii_uppercase: bad argument 1",
          )
      }
      let value = @builtin.Char::to_ascii_uppercase(a0)
      @abi.Ok(enc_builtin_Char(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Char::to_int" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::to_int: bad argument 1",
          )
      }
      let value = @builtin.Char::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Char::to_string" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::to_string: bad argument 1",
          )
      }
      let value = @builtin.Char::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Char::utf16_len" => {
      let a0 = match dec_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Char::utf16_len: bad argument 1",
          )
      }
      let value = @builtin.Char::utf16_len(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::abs" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::abs: bad argument 1",
          )
      }
      let value = @builtin.Int64::abs(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::add" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::add: bad argument 2",
          )
      }
      let value = @builtin.Int64::add(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::clz" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::clz: bad argument 1",
          )
      }
      let value = @builtin.Int64::clz(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::compare" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::compare: bad argument 2",
          )
      }
      let value = @builtin.Int64::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::ctz" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::ctz: bad argument 1",
          )
      }
      let value = @builtin.Int64::ctz(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::div" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::div: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::div: bad argument 2",
          )
      }
      let value = @builtin.Int64::div(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::equal" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::equal: bad argument 2",
          )
      }
      let value = @builtin.Int64::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::from_int" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::from_int: bad argument 1",
          )
      }
      let value = @builtin.Int64::from_int(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::hash" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::hash: bad argument 1",
          )
      }
      let value = @builtin.Int64::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::land" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::land: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::land: bad argument 2",
          )
      }
      let value = @builtin.Int64::land(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::lnot" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::lnot: bad argument 1",
          )
      }
      let value = @builtin.Int64::lnot(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::lor" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::lor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::lor: bad argument 2",
          )
      }
      let value = @builtin.Int64::lor(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::lxor" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::lxor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::lxor: bad argument 2",
          )
      }
      let value = @builtin.Int64::lxor(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::max" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::max: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::max: bad argument 2",
          )
      }
      let value = @builtin.Int64::max(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::min" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::min: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::min: bad argument 2",
          )
      }
      let value = @builtin.Int64::min(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::mod" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::mod: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::mod: bad argument 2",
          )
      }
      let value = @builtin.Int64::mod(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::mul" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::mul: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::mul: bad argument 2",
          )
      }
      let value = @builtin.Int64::mul(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::neg" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::neg: bad argument 1",
          )
      }
      let value = @builtin.Int64::neg(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::popcnt" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::popcnt: bad argument 1",
          )
      }
      let value = @builtin.Int64::popcnt(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::reinterpret_as_double" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::reinterpret_as_double: bad argument 1",
          )
      }
      let value = @builtin.Int64::reinterpret_as_double(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::reinterpret_as_uint64" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::reinterpret_as_uint64: bad argument 1",
          )
      }
      let value = @builtin.Int64::reinterpret_as_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::sub" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::sub: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::sub: bad argument 2",
          )
      }
      let value = @builtin.Int64::sub(a0, a1)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::to_byte" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::to_byte: bad argument 1",
          )
      }
      let value = @builtin.Int64::to_byte(a0)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Int64::to_double" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::to_double: bad argument 1",
          )
      }
      let value = @builtin.Int64::to_double(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::to_int" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::to_int: bad argument 1",
          )
      }
      let value = @builtin.Int64::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::to_string" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::to_string: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.Int64::to_string(a0, radix=v1)
        None => @builtin.Int64::to_string(a0)
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Int64::to_uint16" => {
      let a0 = match dec_builtin_Int64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Int64::to_uint16: bad argument 1",
          )
      }
      let value = @builtin.Int64::to_uint16(a0)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::add" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::add: bad argument 2",
          )
      }
      let value = @builtin.UInt16::add(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::compare" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::compare: bad argument 2",
          )
      }
      let value = @builtin.UInt16::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::div" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::div: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::div: bad argument 2",
          )
      }
      let value = @builtin.UInt16::div(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::equal" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::equal: bad argument 2",
          )
      }
      let value = @builtin.UInt16::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::hash" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::hash: bad argument 1",
          )
      }
      let value = @builtin.UInt16::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::is_leading_surrogate" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::is_leading_surrogate: bad argument 1",
          )
      }
      let value = @builtin.UInt16::is_leading_surrogate(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::is_surrogate" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::is_surrogate: bad argument 1",
          )
      }
      let value = @builtin.UInt16::is_surrogate(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::is_trailing_surrogate" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::is_trailing_surrogate: bad argument 1",
          )
      }
      let value = @builtin.UInt16::is_trailing_surrogate(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::land" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::land: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::land: bad argument 2",
          )
      }
      let value = @builtin.UInt16::land(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::lnot" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::lnot: bad argument 1",
          )
      }
      let value = @builtin.UInt16::lnot(a0)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::lor" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::lor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::lor: bad argument 2",
          )
      }
      let value = @builtin.UInt16::lor(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::lxor" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::lxor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::lxor: bad argument 2",
          )
      }
      let value = @builtin.UInt16::lxor(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::mod" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::mod: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::mod: bad argument 2",
          )
      }
      let value = @builtin.UInt16::mod(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::mul" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::mul: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::mul: bad argument 2",
          )
      }
      let value = @builtin.UInt16::mul(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::shl" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::shl: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::shl: bad argument 2",
          )
      }
      let value = @builtin.UInt16::shl(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::shr" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::shr: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::shr: bad argument 2",
          )
      }
      let value = @builtin.UInt16::shr(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::sub" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::sub: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::sub: bad argument 2",
          )
      }
      let value = @builtin.UInt16::sub(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::to_byte" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_byte: bad argument 1",
          )
      }
      let value = @builtin.UInt16::to_byte(a0)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::to_char" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_char: bad argument 1",
          )
      }
      let value = @builtin.UInt16::to_char(a0)
      @abi.Ok(enc_builtin_Char(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::to_int" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_int: bad argument 1",
          )
      }
      let value = @builtin.UInt16::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::to_int64" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_int64: bad argument 1",
          )
      }
      let value = @builtin.UInt16::to_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt16::to_string" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_string: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.UInt16::to_string(a0, radix=v1)
        None => @builtin.UInt16::to_string(a0)
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::UInt16::to_uint64" => {
      let a0 = match dec_builtin_UInt16(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt16::to_uint64: bad argument 1",
          )
      }
      let value = @builtin.UInt16::to_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::add" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::add: bad argument 2",
          )
      }
      let value = @builtin.UInt64::add(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::clz" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::clz: bad argument 1",
          )
      }
      let value = @builtin.UInt64::clz(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::compare" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::compare: bad argument 2",
          )
      }
      let value = @builtin.UInt64::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::ctz" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::ctz: bad argument 1",
          )
      }
      let value = @builtin.UInt64::ctz(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::div" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::div: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::div: bad argument 2",
          )
      }
      let value = @builtin.UInt64::div(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::equal" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::equal: bad argument 2",
          )
      }
      let value = @builtin.UInt64::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::hash" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::hash: bad argument 1",
          )
      }
      let value = @builtin.UInt64::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::land" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::land: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::land: bad argument 2",
          )
      }
      let value = @builtin.UInt64::land(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::lnot" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::lnot: bad argument 1",
          )
      }
      let value = @builtin.UInt64::lnot(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::lor" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::lor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::lor: bad argument 2",
          )
      }
      let value = @builtin.UInt64::lor(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::lxor" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::lxor: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::lxor: bad argument 2",
          )
      }
      let value = @builtin.UInt64::lxor(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::max" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::max: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::max: bad argument 2",
          )
      }
      let value = @builtin.UInt64::max(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::min" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::min: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::min: bad argument 2",
          )
      }
      let value = @builtin.UInt64::min(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::mod" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::mod: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::mod: bad argument 2",
          )
      }
      let value = @builtin.UInt64::mod(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::mul" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::mul: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::mul: bad argument 2",
          )
      }
      let value = @builtin.UInt64::mul(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::popcnt" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::popcnt: bad argument 1",
          )
      }
      let value = @builtin.UInt64::popcnt(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::reinterpret_as_double" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::reinterpret_as_double: bad argument 1",
          )
      }
      let value = @builtin.UInt64::reinterpret_as_double(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::reinterpret_as_int64" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::reinterpret_as_int64: bad argument 1",
          )
      }
      let value = @builtin.UInt64::reinterpret_as_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::sub" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::sub: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::sub: bad argument 2",
          )
      }
      let value = @builtin.UInt64::sub(a0, a1)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::to_be_bytes" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_be_bytes: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_be_bytes(a0)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::to_byte" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_byte: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_byte(a0)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::to_double" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_double: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_double(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::to_int" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_int: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::to_le_bytes" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_le_bytes: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_le_bytes(a0)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::to_string" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_string: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.UInt64::to_string(a0, radix=v1)
        None => @builtin.UInt64::to_string(a0)
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::UInt64::to_uint16" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::to_uint16: bad argument 1",
          )
      }
      let value = @builtin.UInt64::to_uint16(a0)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::UInt64::trunc_double" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::UInt64::trunc_double: bad argument 1",
          )
      }
      let value = @builtin.UInt64::trunc_double(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Double::abs" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::abs: bad argument 1",
          )
      }
      let value = @builtin.Double::abs(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::add" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::add: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::add: bad argument 2",
          )
      }
      let value = @builtin.Double::add(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::ceil" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::ceil: bad argument 1",
          )
      }
      let value = @builtin.Double::ceil(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::compare" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::compare: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::compare: bad argument 2",
          )
      }
      let value = @builtin.Double::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Double::convert_uint64" => {
      let a0 = match dec_builtin_UInt64(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::convert_uint64: bad argument 1",
          )
      }
      let value = @builtin.Double::convert_uint64(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::div" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::div: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::div: bad argument 2",
          )
      }
      let value = @builtin.Double::div(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::equal" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::equal: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::equal: bad argument 2",
          )
      }
      let value = @builtin.Double::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::floor" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::floor: bad argument 1",
          )
      }
      let value = @builtin.Double::floor(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::from_int" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::from_int: bad argument 1",
          )
      }
      let value = @builtin.Double::from_int(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::hash" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::hash: bad argument 1",
          )
      }
      let value = @builtin.Double::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_close" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_close: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_close: bad argument 2",
          )
      }
      let a2 = dec_double(arg(argv, 2))
      let a3 = dec_double(arg(argv, 3))
      let value = match a2 {
        Some(v2) =>
          match a3 {
            Some(v3) =>
              @builtin.Double::is_close(
                a0,
                a1,
                relative_tolerance=v2,
                absolute_tolerance=v3,
              )
            None => @builtin.Double::is_close(a0, a1, relative_tolerance=v2)
          }
        None =>
          match a3 {
            Some(v3) => @builtin.Double::is_close(a0, a1, absolute_tolerance=v3)
            None => @builtin.Double::is_close(a0, a1)
          }
      }
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_finite" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_finite: bad argument 1",
          )
      }
      let value = @builtin.Double::is_finite(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_inf" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_inf: bad argument 1",
          )
      }
      let value = @builtin.Double::is_inf(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_nan" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_nan: bad argument 1",
          )
      }
      let value = @builtin.Double::is_nan(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_neg_inf" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_neg_inf: bad argument 1",
          )
      }
      let value = @builtin.Double::is_neg_inf(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::is_pos_inf" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::is_pos_inf: bad argument 1",
          )
      }
      let value = @builtin.Double::is_pos_inf(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Double::max" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::max: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::max: bad argument 2",
          )
      }
      let value = @builtin.Double::max(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::min" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::min: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::min: bad argument 2",
          )
      }
      let value = @builtin.Double::min(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::mod" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::mod: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::mod: bad argument 2",
          )
      }
      let value = @builtin.Double::mod(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::mul" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::mul: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::mul: bad argument 2",
          )
      }
      let value = @builtin.Double::mul(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::neg" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::neg: bad argument 1",
          )
      }
      let value = @builtin.Double::neg(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::reinterpret_as_int64" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::reinterpret_as_int64: bad argument 1",
          )
      }
      let value = @builtin.Double::reinterpret_as_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Double::reinterpret_as_uint64" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::reinterpret_as_uint64: bad argument 1",
          )
      }
      let value = @builtin.Double::reinterpret_as_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Double::round" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::round: bad argument 1",
          )
      }
      let value = @builtin.Double::round(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::signum" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::signum: bad argument 1",
          )
      }
      let value = @builtin.Double::signum(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::sqrt" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::sqrt: bad argument 1",
          )
      }
      let value = @builtin.Double::sqrt(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::sub" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::sub: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::sub: bad argument 2",
          )
      }
      let value = @builtin.Double::sub(a0, a1)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::Double::to_int" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::to_int: bad argument 1",
          )
      }
      let value = @builtin.Double::to_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Double::to_int64" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::to_int64: bad argument 1",
          )
      }
      let value = @builtin.Double::to_int64(a0)
      @abi.Ok(enc_builtin_Int64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Double::to_string" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::to_string: bad argument 1",
          )
      }
      let value = @builtin.Double::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Double::to_uint64" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::to_uint64: bad argument 1",
          )
      }
      let value = @builtin.Double::to_uint64(a0)
      @abi.Ok(enc_builtin_UInt64(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Double::total_compare" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::total_compare: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::total_compare: bad argument 2",
          )
      }
      let value = @builtin.Double::total_compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Double::trunc" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Double::trunc: bad argument 1",
          )
      }
      let value = @builtin.Double::trunc(a0)
      @abi.Ok(enc_double(Some(value)))
    }
    "moonbitlang/core/builtin::String::add" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::add: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::add: bad argument 2",
          )
      }
      let value = @builtin.String::add(a0, a1)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::after" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::after: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::after: bad argument 2",
          )
      }
      let value = @builtin.String::after(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::at" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::at: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::at: bad argument 2",
          )
      }
      let value = @builtin.String::at(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::String::before" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::before: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::before: bad argument 2",
          )
      }
      let value = @builtin.String::before(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::char_length" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::char_length: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.String::char_length(a0, start=v1, end=v2)
            None => @builtin.String::char_length(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.String::char_length(a0, end=v2)
            None => @builtin.String::char_length(a0)
          }
      }
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::char_length_eq" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::char_length_eq: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::char_length_eq: bad argument 2",
          )
      }
      let a2 = dec_int(arg(argv, 2))
      let a3 = dec_int(arg(argv, 3))
      let value = match a2 {
        Some(v2) =>
          match a3 {
            Some(v3) =>
              @builtin.String::char_length_eq(a0, a1, start=v2, end=v3)
            None => @builtin.String::char_length_eq(a0, a1, start=v2)
          }
        None =>
          match a3 {
            Some(v3) => @builtin.String::char_length_eq(a0, a1, end=v3)
            None => @builtin.String::char_length_eq(a0, a1)
          }
      }
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::char_length_ge" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::char_length_ge: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::char_length_ge: bad argument 2",
          )
      }
      let a2 = dec_int(arg(argv, 2))
      let a3 = dec_int(arg(argv, 3))
      let value = match a2 {
        Some(v2) =>
          match a3 {
            Some(v3) =>
              @builtin.String::char_length_ge(a0, a1, start=v2, end=v3)
            None => @builtin.String::char_length_ge(a0, a1, start=v2)
          }
        None =>
          match a3 {
            Some(v3) => @builtin.String::char_length_ge(a0, a1, end=v3)
            None => @builtin.String::char_length_ge(a0, a1)
          }
      }
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::clamped_view" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::clamped_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.String::clamped_view(a0, start=v1, end=v2)
            None => @builtin.String::clamped_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.String::clamped_view(a0, end=v2)
            None => @builtin.String::clamped_view(a0)
          }
      }
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::String::compare" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::compare: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::compare: bad argument 2",
          )
      }
      let value = @builtin.String::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::compare_ignore_ascii_case" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::compare_ignore_ascii_case: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::compare_ignore_ascii_case: bad argument 2",
          )
      }
      let value = @builtin.String::compare_ignore_ascii_case(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::contains" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains: bad argument 2",
          )
      }
      let value = @builtin.String::contains(a0, a1[:])
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::contains_char" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains_char: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains_char: bad argument 2",
          )
      }
      let value = @builtin.String::contains_char(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::contains_code_unit" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains_code_unit: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::contains_code_unit: bad argument 2",
          )
      }
      let value = @builtin.String::contains_code_unit(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::equal" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::equal: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::equal: bad argument 2",
          )
      }
      let value = @builtin.String::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::equal_ignore_ascii_case" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::equal_ignore_ascii_case: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::equal_ignore_ascii_case: bad argument 2",
          )
      }
      let value = @builtin.String::equal_ignore_ascii_case(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::escape" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::escape: bad argument 1",
          )
      }
      let a1 = dec_bool(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.String::escape(a0, quote=v1)
        None => @builtin.String::escape(a0)
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::exact_view" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::exact_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.String::exact_view(a0, start=v1, end=v2)
            None => @builtin.String::exact_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.String::exact_view(a0, end=v2)
            None => @builtin.String::exact_view(a0)
          }
      }
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::String::find" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::find: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::find: bad argument 2",
          )
      }
      let value = @builtin.String::find(a0, a1[:])
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::String::from_array" => {
      let a0 = match dec_arr_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::from_array: bad argument 1",
          )
      }
      let value = @builtin.String::from_array(a0[:])
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::get" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::get: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::get: bad argument 2",
          )
      }
      let value = @builtin.String::get(a0, a1)
      @abi.Ok(enc_builtin_UInt16(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::String::get_char" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::get_char: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::get_char: bad argument 2",
          )
      }
      let value = @builtin.String::get_char(a0, a1)
      @abi.Ok(enc_builtin_Char(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::String::get_view" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::get_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.String::get_view(a0, start=v1, end=v2)
            None => @builtin.String::get_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.String::get_view(a0, end=v2)
            None => @builtin.String::get_view(a0)
          }
      }
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::has_prefix" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::has_prefix: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::has_prefix: bad argument 2",
          )
      }
      let value = @builtin.String::has_prefix(a0, a1[:])
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::has_suffix" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::has_suffix: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::has_suffix: bad argument 2",
          )
      }
      let value = @builtin.String::has_suffix(a0, a1[:])
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::hash" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::hash: bad argument 1",
          )
      }
      let value = @builtin.String::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::is_blank" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::is_blank: bad argument 1",
          )
      }
      let value = @builtin.String::is_blank(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::is_empty" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::is_empty: bad argument 1",
          )
      }
      let value = @builtin.String::is_empty(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::String::length" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::length: bad argument 1",
          )
      }
      let value = @builtin.String::length(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::lexical_compare" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::lexical_compare: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::lexical_compare: bad argument 2",
          )
      }
      let value = @builtin.String::lexical_compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::String::make" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::make: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::make: bad argument 2",
          )
      }
      let value = @builtin.String::make(a0, a1)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::offset_of_nth_char" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::offset_of_nth_char: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::offset_of_nth_char: bad argument 2",
          )
      }
      let a2 = dec_int(arg(argv, 2))
      let a3 = dec_int(arg(argv, 3))
      let value = match a2 {
        Some(v2) =>
          match a3 {
            Some(v3) =>
              @builtin.String::offset_of_nth_char(a0, a1, start=v2, end=v3)
            None => @builtin.String::offset_of_nth_char(a0, a1, start=v2)
          }
        None =>
          match a3 {
            Some(v3) => @builtin.String::offset_of_nth_char(a0, a1, end=v3)
            None => @builtin.String::offset_of_nth_char(a0, a1)
          }
      }
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::String::pad_end" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_end: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_end: bad argument 2",
          )
      }
      let a2 = match dec_builtin_Char(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_end: bad argument 3",
          )
      }
      let value = @builtin.String::pad_end(a0, a1, a2)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::pad_start" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_start: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_start: bad argument 2",
          )
      }
      let a2 = match dec_builtin_Char(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::pad_start: bad argument 3",
          )
      }
      let value = @builtin.String::pad_start(a0, a1, a2)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::repeat" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::repeat: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::repeat: bad argument 2",
          )
      }
      let value = @builtin.String::repeat(a0, a1)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::rev" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev: bad argument 1",
          )
      }
      let value = @builtin.String::rev(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::rev_after" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_after: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_after: bad argument 2",
          )
      }
      let value = @builtin.String::rev_after(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::rev_before" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_before: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_before: bad argument 2",
          )
      }
      let value = @builtin.String::rev_before(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::rev_find" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_find: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::rev_find: bad argument 2",
          )
      }
      let value = @builtin.String::rev_find(a0, a1[:])
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::String::strip_prefix" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::strip_prefix: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::strip_prefix: bad argument 2",
          )
      }
      let value = @builtin.String::strip_prefix(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::strip_suffix" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::strip_suffix: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::strip_suffix: bad argument 2",
          )
      }
      let value = @builtin.String::strip_suffix(a0, a1[:])
      @abi.Ok(enc_strview(value))
    }
    "moonbitlang/core/builtin::String::to_array" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::to_array: bad argument 1",
          )
      }
      let value = @builtin.String::to_array(a0)
      @abi.Ok(enc_arr_builtin_Char(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::String::to_lower" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::to_lower: bad argument 1",
          )
      }
      let value = @builtin.String::to_lower(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::to_string" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::to_string: bad argument 1",
          )
      }
      let value = @builtin.String::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::to_string_view" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::to_string_view: bad argument 1",
          )
      }
      let value = @builtin.String::to_string_view(a0)
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::String::to_upper" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::to_upper: bad argument 1",
          )
      }
      let value = @builtin.String::to_upper(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::String::trim" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::trim: bad argument 1",
          )
      }
      let a1 = dec_str(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.String::trim(a0, chars=v1[:])
        None => @builtin.String::trim(a0)
      }
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::String::trim_end" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::trim_end: bad argument 1",
          )
      }
      let a1 = dec_str(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.String::trim_end(a0, chars=v1[:])
        None => @builtin.String::trim_end(a0)
      }
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::String::trim_start" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::String::trim_start: bad argument 1",
          )
      }
      let a1 = dec_str(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.String::trim_start(a0, chars=v1[:])
        None => @builtin.String::trim_start(a0)
      }
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/builtin::V128::equal" => {
      let a0 = match dec_builtin_V128(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::V128::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_V128(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::V128::equal: bad argument 2",
          )
      }
      let value = @builtin.V128::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::V128::to_string" => {
      let a0 = match dec_builtin_V128(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::V128::to_string: bad argument 1",
          )
      }
      let value = @builtin.V128::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::add" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::add: bad argument 2",
          )
      }
      let value = @builtin.Bytes::add(a0, a1)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::at" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::at: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::at: bad argument 2",
          )
      }
      let value = @builtin.Bytes::at(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::clamped_view" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::clamped_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.Bytes::clamped_view(a0, start=v1, end=v2)
            None => @builtin.Bytes::clamped_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.Bytes::clamped_view(a0, end=v2)
            None => @builtin.Bytes::clamped_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::compare" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::compare: bad argument 2",
          )
      }
      let value = @builtin.Bytes::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::equal" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::equal: bad argument 2",
          )
      }
      let value = @builtin.Bytes::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::exact_view" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::exact_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.Bytes::exact_view(a0, start=v1, end=v2)
            None => @builtin.Bytes::exact_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.Bytes::exact_view(a0, end=v2)
            None => @builtin.Bytes::exact_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::find" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::find: bad argument 2",
          )
      }
      let value = @builtin.Bytes::find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::Bytes::from_array" => {
      let a0 = match dec_arr_builtin_Byte(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::from_array: bad argument 1",
          )
      }
      let value = @builtin.Bytes::from_array(a0[:])
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::get" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::get: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::get: bad argument 2",
          )
      }
      let value = @builtin.Bytes::get(a0, a1)
      @abi.Ok(enc_builtin_Byte(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::get_view" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::get_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.Bytes::get_view(a0, start=v1, end=v2)
            None => @builtin.Bytes::get_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.Bytes::get_view(a0, end=v2)
            None => @builtin.Bytes::get_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::has_prefix" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::has_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::has_prefix: bad argument 2",
          )
      }
      let value = @builtin.Bytes::has_prefix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::has_suffix" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::has_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::has_suffix: bad argument 2",
          )
      }
      let value = @builtin.Bytes::has_suffix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::hash" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::hash: bad argument 1",
          )
      }
      let value = @builtin.Bytes::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::is_empty" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::is_empty: bad argument 1",
          )
      }
      let value = @builtin.Bytes::is_empty(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::length" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::length: bad argument 1",
          )
      }
      let value = @builtin.Bytes::length(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::lexical_compare" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::lexical_compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::lexical_compare: bad argument 2",
          )
      }
      let value = @builtin.Bytes::lexical_compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::make" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::make: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::make: bad argument 2",
          )
      }
      let value = @builtin.Bytes::make(a0, a1)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::new" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::new: bad argument 1",
          )
      }
      let value = @builtin.Bytes::new(a0)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::repeat" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::repeat: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::repeat: bad argument 2",
          )
      }
      let value = @builtin.Bytes::repeat(a0, a1)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::rev_find" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::rev_find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::rev_find: bad argument 2",
          )
      }
      let value = @builtin.Bytes::rev_find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::Bytes::strip_prefix" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::strip_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::strip_prefix: bad argument 2",
          )
      }
      let value = @builtin.Bytes::strip_prefix(a0, a1)
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::strip_suffix" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::strip_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::strip_suffix: bad argument 2",
          )
      }
      let value = @builtin.Bytes::strip_suffix(a0, a1)
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::to_array" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::to_array: bad argument 1",
          )
      }
      let value = @builtin.Bytes::to_array(a0)
      @abi.Ok(enc_arr_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Bytes::to_string" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::to_string: bad argument 1",
          )
      }
      let value = @builtin.Bytes::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Bytes::to_unchecked_string" => {
      let a0 = match dec_builtin_Bytes(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Bytes::to_unchecked_string: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) =>
              @builtin.Bytes::to_unchecked_string(a0, offset=v1, length=v2)
            None => @builtin.Bytes::to_unchecked_string(a0, offset=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.Bytes::to_unchecked_string(a0, length=v2)
            None => @builtin.Bytes::to_unchecked_string(a0)
          }
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Error::to_string" => {
      let a0 = match dec_builtin_Error(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Error::to_string: bad argument 1",
          )
      }
      let value = @builtin.Error::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::ArgsLoc::to_json" => {
      let a0 = match dec_builtin_ArgsLoc(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::ArgsLoc::to_json: bad argument 1",
          )
      }
      let value = @builtin.ArgsLoc::to_json(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::ArgsLoc::to_string" => {
      let a0 = match dec_builtin_ArgsLoc(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::ArgsLoc::to_string: bad argument 1",
          )
      }
      let value = @builtin.ArgsLoc::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_bool" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_bool: bad argument 1",
          )
      }
      let a1 = match dec_bool(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_bool: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_bool(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_byte" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_byte: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Byte(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_byte: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_byte(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_bytes" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_bytes: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_bytes: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_bytes(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_char" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_char: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_char: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_char(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_double" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_double: bad argument 1",
          )
      }
      let a1 = match dec_double(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_double: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_double(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_int" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_int: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_int: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_int(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_int64" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_int64: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Int64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_int64: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_int64(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_string" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_string: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_string: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_string(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_uint64" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_uint64: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt64(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_uint64: bad argument 2",
          )
      }
      let value = @builtin.Hasher::combine_uint64(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::combine_unit" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::combine_unit: bad argument 1",
          )
      }
      let value = @builtin.Hasher::combine_unit(a0)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::Hasher::finalize" => {
      let a0 = match dec_builtin_Hasher(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Hasher::finalize: bad argument 1",
          )
      }
      let value = @builtin.Hasher::finalize(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::SourceLoc::to_json_string" => {
      let a0 = match dec_builtin_SourceLoc(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::SourceLoc::to_json_string: bad argument 1",
          )
      }
      let value = @builtin.SourceLoc::to_json_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::SourceLoc::to_string" => {
      let a0 = match dec_builtin_SourceLoc(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::SourceLoc::to_string: bad argument 1",
          )
      }
      let value = @builtin.SourceLoc::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::is_empty" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::is_empty: bad argument 1",
          )
      }
      let value = @builtin.StringBuilder::is_empty(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::reset" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::reset: bad argument 1",
          )
      }
      let a1 = dec_bool(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.StringBuilder::reset(a0, keep_capacity=v1)
        None => @builtin.StringBuilder::reset(a0)
      }
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::to_string" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::to_string: bad argument 1",
          )
      }
      let value = @builtin.StringBuilder::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::write_char" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_char: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_char: bad argument 2",
          )
      }
      let value = @builtin.StringBuilder::write_char(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::write_string" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_string: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_string: bad argument 2",
          )
      }
      let value = @builtin.StringBuilder::write_string(a0, a1)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::write_stringview" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_stringview: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_stringview: bad argument 2",
          )
      }
      let value = @builtin.StringBuilder::write_stringview(a0, a1[:])
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::write_substring" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_substring: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_substring: bad argument 2",
          )
      }
      let a2 = match dec_int(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_substring: bad argument 3",
          )
      }
      let a3 = match dec_int(arg(argv, 3)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_substring: bad argument 4",
          )
      }
      let value = @builtin.StringBuilder::write_substring(a0, a1, a2, a3)
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::StringBuilder::write_view" => {
      let a0 = match dec_builtin_StringBuilder(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_view: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringBuilder::write_view: bad argument 2",
          )
      }
      let value = @builtin.StringBuilder::write_view(a0, a1[:])
      @abi.Ok(enc_unit(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::at" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::at: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::at: bad argument 2",
          )
      }
      let value = @builtin.BytesView::at(a0, a1)
      @abi.Ok(enc_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::clamped_view" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::clamped_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.BytesView::clamped_view(a0, start=v1, end=v2)
            None => @builtin.BytesView::clamped_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.BytesView::clamped_view(a0, end=v2)
            None => @builtin.BytesView::clamped_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::compare" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::compare: bad argument 2",
          )
      }
      let value = @builtin.BytesView::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::data" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::data: bad argument 1",
          )
      }
      let value = @builtin.BytesView::data(a0)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::equal" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::equal: bad argument 2",
          )
      }
      let value = @builtin.BytesView::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::equal_to_bytes" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::equal_to_bytes: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Bytes(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::equal_to_bytes: bad argument 2",
          )
      }
      let value = @builtin.BytesView::equal_to_bytes(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::exact_view" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::exact_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.BytesView::exact_view(a0, start=v1, end=v2)
            None => @builtin.BytesView::exact_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.BytesView::exact_view(a0, end=v2)
            None => @builtin.BytesView::exact_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::find" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::find: bad argument 2",
          )
      }
      let value = @builtin.BytesView::find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::BytesView::get" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::get: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::get: bad argument 2",
          )
      }
      let value = @builtin.BytesView::get(a0, a1)
      @abi.Ok(enc_builtin_Byte(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::get_view" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::get_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.BytesView::get_view(a0, start=v1, end=v2)
            None => @builtin.BytesView::get_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.BytesView::get_view(a0, end=v2)
            None => @builtin.BytesView::get_view(a0)
          }
      }
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::has_prefix" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::has_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::has_prefix: bad argument 2",
          )
      }
      let value = @builtin.BytesView::has_prefix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::has_suffix" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::has_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::has_suffix: bad argument 2",
          )
      }
      let value = @builtin.BytesView::has_suffix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::hash" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::hash: bad argument 1",
          )
      }
      let value = @builtin.BytesView::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::is_empty" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::is_empty: bad argument 1",
          )
      }
      let value = @builtin.BytesView::is_empty(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::length" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::length: bad argument 1",
          )
      }
      let value = @builtin.BytesView::length(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::lexical_compare" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::lexical_compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::lexical_compare: bad argument 2",
          )
      }
      let value = @builtin.BytesView::lexical_compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::rev_find" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::rev_find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::rev_find: bad argument 2",
          )
      }
      let value = @builtin.BytesView::rev_find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::BytesView::start_offset" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::start_offset: bad argument 1",
          )
      }
      let value = @builtin.BytesView::start_offset(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::BytesView::strip_prefix" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::strip_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::strip_prefix: bad argument 2",
          )
      }
      let value = @builtin.BytesView::strip_prefix(a0, a1)
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::strip_suffix" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::strip_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_BytesView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::strip_suffix: bad argument 2",
          )
      }
      let value = @builtin.BytesView::strip_suffix(a0, a1)
      @abi.Ok(enc_builtin_BytesView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::to_array" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::to_array: bad argument 1",
          )
      }
      let value = @builtin.BytesView::to_array(a0)
      @abi.Ok(enc_arr_builtin_Byte(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::to_owned" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::to_owned: bad argument 1",
          )
      }
      let value = @builtin.BytesView::to_owned(a0)
      @abi.Ok(enc_builtin_Bytes(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::BytesView::to_string" => {
      let a0 = match dec_builtin_BytesView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::BytesView::to_string: bad argument 1",
          )
      }
      let value = @builtin.BytesView::to_string(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::add" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::add: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::add: bad argument 2",
          )
      }
      let value = @builtin.StringView::add(a0, a1)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::after" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::after: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::after: bad argument 2",
          )
      }
      let value = @builtin.StringView::after(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::at" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::at: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::at: bad argument 2",
          )
      }
      let value = @builtin.StringView::at(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::before" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::before: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::before: bad argument 2",
          )
      }
      let value = @builtin.StringView::before(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::char_length" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::char_length: bad argument 1",
          )
      }
      let value = @builtin.StringView::char_length(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::char_length_eq" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::char_length_eq: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::char_length_eq: bad argument 2",
          )
      }
      let value = @builtin.StringView::char_length_eq(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::char_length_ge" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::char_length_ge: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::char_length_ge: bad argument 2",
          )
      }
      let value = @builtin.StringView::char_length_ge(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::clamped_view" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::clamped_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.StringView::clamped_view(a0, start=v1, end=v2)
            None => @builtin.StringView::clamped_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.StringView::clamped_view(a0, end=v2)
            None => @builtin.StringView::clamped_view(a0)
          }
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::compare" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::compare: bad argument 2",
          )
      }
      let value = @builtin.StringView::compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::compare_ignore_ascii_case" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::compare_ignore_ascii_case: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::compare_ignore_ascii_case: bad argument 2",
          )
      }
      let value = @builtin.StringView::compare_ignore_ascii_case(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::contains" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains: bad argument 2",
          )
      }
      let value = @builtin.StringView::contains(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::contains_char" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains_char: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains_char: bad argument 2",
          )
      }
      let value = @builtin.StringView::contains_char(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::contains_code_unit" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains_code_unit: bad argument 1",
          )
      }
      let a1 = match dec_builtin_UInt16(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::contains_code_unit: bad argument 2",
          )
      }
      let value = @builtin.StringView::contains_code_unit(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::data" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::data: bad argument 1",
          )
      }
      let value = @builtin.StringView::data(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::equal" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal: bad argument 2",
          )
      }
      let value = @builtin.StringView::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::equal_ignore_ascii_case" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal_ignore_ascii_case: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal_ignore_ascii_case: bad argument 2",
          )
      }
      let value = @builtin.StringView::equal_ignore_ascii_case(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::equal_to_string" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal_to_string: bad argument 1",
          )
      }
      let a1 = match dec_str(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::equal_to_string: bad argument 2",
          )
      }
      let value = @builtin.StringView::equal_to_string(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::escape" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::escape: bad argument 1",
          )
      }
      let a1 = dec_bool(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.StringView::escape(a0, quote=v1)
        None => @builtin.StringView::escape(a0)
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::exact_view" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::exact_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.StringView::exact_view(a0, start=v1, end=v2)
            None => @builtin.StringView::exact_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.StringView::exact_view(a0, end=v2)
            None => @builtin.StringView::exact_view(a0)
          }
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::find" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::find: bad argument 2",
          )
      }
      let value = @builtin.StringView::find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::StringView::from_array" => {
      let a0 = match dec_arr_builtin_Char(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::from_array: bad argument 1",
          )
      }
      let value = @builtin.StringView::from_array(a0[:])
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::get" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::get: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::get: bad argument 2",
          )
      }
      let value = @builtin.StringView::get(a0, a1)
      @abi.Ok(enc_builtin_UInt16(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::get_char" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::get_char: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::get_char: bad argument 2",
          )
      }
      let value = @builtin.StringView::get_char(a0, a1)
      @abi.Ok(enc_builtin_Char(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::get_view" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::get_view: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let a2 = dec_int(arg(argv, 2))
      let value = match a1 {
        Some(v1) =>
          match a2 {
            Some(v2) => @builtin.StringView::get_view(a0, start=v1, end=v2)
            None => @builtin.StringView::get_view(a0, start=v1)
          }
        None =>
          match a2 {
            Some(v2) => @builtin.StringView::get_view(a0, end=v2)
            None => @builtin.StringView::get_view(a0)
          }
      }
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::has_prefix" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::has_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::has_prefix: bad argument 2",
          )
      }
      let value = @builtin.StringView::has_prefix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::has_suffix" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::has_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::has_suffix: bad argument 2",
          )
      }
      let value = @builtin.StringView::has_suffix(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::hash" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::hash: bad argument 1",
          )
      }
      let value = @builtin.StringView::hash(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::is_blank" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::is_blank: bad argument 1",
          )
      }
      let value = @builtin.StringView::is_blank(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::is_empty" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::is_empty: bad argument 1",
          )
      }
      let value = @builtin.StringView::is_empty(a0)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::length" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::length: bad argument 1",
          )
      }
      let value = @builtin.StringView::length(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::lexical_compare" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::lexical_compare: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::lexical_compare: bad argument 2",
          )
      }
      let value = @builtin.StringView::lexical_compare(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::make" => {
      let a0 = match dec_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::make: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Char(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::make: bad argument 2",
          )
      }
      let value = @builtin.StringView::make(a0, a1)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::offset_of_nth_char" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::offset_of_nth_char: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::offset_of_nth_char: bad argument 2",
          )
      }
      let value = @builtin.StringView::offset_of_nth_char(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::StringView::pad_end" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_end: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_end: bad argument 2",
          )
      }
      let a2 = match dec_builtin_Char(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_end: bad argument 3",
          )
      }
      let value = @builtin.StringView::pad_end(a0, a1, a2)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::pad_start" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_start: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_start: bad argument 2",
          )
      }
      let a2 = match dec_builtin_Char(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::pad_start: bad argument 3",
          )
      }
      let value = @builtin.StringView::pad_start(a0, a1, a2)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::repeat" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::repeat: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::repeat: bad argument 2",
          )
      }
      let value = @builtin.StringView::repeat(a0, a1)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::rev" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev: bad argument 1",
          )
      }
      let value = @builtin.StringView::rev(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::rev_after" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_after: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_after: bad argument 2",
          )
      }
      let value = @builtin.StringView::rev_after(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::rev_before" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_before: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_before: bad argument 2",
          )
      }
      let value = @builtin.StringView::rev_before(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::rev_find" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_find: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::rev_find: bad argument 2",
          )
      }
      let value = @builtin.StringView::rev_find(a0, a1)
      @abi.Ok(enc_int(value))
    }
    "moonbitlang/core/builtin::StringView::start_offset" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::start_offset: bad argument 1",
          )
      }
      let value = @builtin.StringView::start_offset(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::strip_prefix" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::strip_prefix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::strip_prefix: bad argument 2",
          )
      }
      let value = @builtin.StringView::strip_prefix(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::strip_suffix" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::strip_suffix: bad argument 1",
          )
      }
      let a1 = match dec_builtin_StringView(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::strip_suffix: bad argument 2",
          )
      }
      let value = @builtin.StringView::strip_suffix(a0, a1)
      @abi.Ok(enc_builtin_StringView(value)) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::to_array" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::to_array: bad argument 1",
          )
      }
      let value = @builtin.StringView::to_array(a0)
      @abi.Ok(enc_arr_builtin_Char(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::to_lower" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::to_lower: bad argument 1",
          )
      }
      let value = @builtin.StringView::to_lower(a0)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::to_owned" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::to_owned: bad argument 1",
          )
      }
      let value = @builtin.StringView::to_owned(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/builtin::StringView::to_string_view" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::to_string_view: bad argument 1",
          )
      }
      let value = @builtin.StringView::to_string_view(a0)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::to_upper" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::to_upper: bad argument 1",
          )
      }
      let value = @builtin.StringView::to_upper(a0)
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::trim" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::trim: bad argument 1",
          )
      }
      let a1 = dec_builtin_StringView(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.StringView::trim(a0, chars=v1)
        None => @builtin.StringView::trim(a0)
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::trim_end" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::trim_end: bad argument 1",
          )
      }
      let a1 = dec_builtin_StringView(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.StringView::trim_end(a0, chars=v1)
        None => @builtin.StringView::trim_end(a0)
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::trim_start" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::trim_start: bad argument 1",
          )
      }
      let a1 = dec_builtin_StringView(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.StringView::trim_start(a0, chars=v1)
        None => @builtin.StringView::trim_start(a0)
      }
      @abi.Ok(enc_builtin_StringView(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::StringView::unsafe_get" => {
      let a0 = match dec_builtin_StringView(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::unsafe_get: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::StringView::unsafe_get: bad argument 2",
          )
      }
      let value = @builtin.StringView::unsafe_get(a0, a1)
      @abi.Ok(enc_builtin_UInt16(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/lexbuf::Lexbuf::from_fn" => {
      let a0 = match dec_cb__to_opt_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::Lexbuf::from_fn: bad argument 1",
          )
      }
      let value = @lexbuf.Lexbuf::from_fn(a0)
      @abi.Ok(enc_lexbuf_Lexbuf(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/lexbuf::StringScanner::__new__" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__new__: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__new__: bad argument 2",
          )
      }
      let value = @lexbuf.StringScanner::{ data: a0[:], cursor: a1, }
      @abi.Ok(enc_lexbuf_StringScanner(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/lexbuf::StringScanner::__get_data" => {
      let a0 = match dec_lexbuf_StringScanner(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__get_data: bad argument 1",
          )
      }
      let value = a0.data
      @abi.Ok(enc_strview(Some(value)))
    }
    "moonbitlang/core/lexbuf::StringScanner::__get_cursor" => {
      let a0 = match dec_lexbuf_StringScanner(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__get_cursor: bad argument 1",
          )
      }
      let value = a0.cursor
      @abi.Ok(enc_int(Some(value)))
    }
    "moonbitlang/core/lexbuf::StringScanner::__set_cursor" => {
      let id = match arg_handle(argv, 0) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__set_cursor: bad argument 1",
          )
      }
      let value = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__set_cursor: bad argument 2",
          )
      }
      match tables.lexbuf_StringScanner.get(id) {
        Some(slot) => {
          let current = slot.val
          current.cursor = value
          slot.val = current
          @abi.Ok(@abi.Value::unit())
        }
        None =>
          @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::__set_cursor: stale handle",
          )
      }
    }
    "moonbitlang/core/lexbuf::StringScanner::StringScanner" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/lexbuf::StringScanner::StringScanner: bad argument 1",
          )
      }
      let a1 = dec_int(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @lexbuf.StringScanner::StringScanner(a0[:], cursor=v1)
        None => @lexbuf.StringScanner::StringScanner(a0[:])
      }
      @abi.Ok(enc_lexbuf_StringScanner(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "gyyyy6/moonbridge/callbacks::call_both" => {
      let a0 = match dec_cb__to_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_both: bad argument 1",
          )
      }
      let a1 = match dec_cb_int_to_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_both: bad argument 2",
          )
      }
      let a2 = match dec_int(arg(argv, 2)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_both: bad argument 3",
          )
      }
      let value = @callbacks.call_both(a0, a1, a2)
      @abi.Ok(enc_int(Some(value)))
    }
    "gyyyy6/moonbridge/callbacks::call_int" => {
      let a0 = match dec_cb__to_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_int: bad argument 1",
          )
      }
      let value = @callbacks.call_int(a0)
      @abi.Ok(enc_int(Some(value)))
    }
    "gyyyy6/moonbridge/callbacks::call_opt" => {
      let a0 = match dec_cb__to_opt_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_opt: bad argument 1",
          )
      }
      let value = @callbacks.call_opt(a0)
      @abi.Ok(enc_str(Some(value)))
    }
    "gyyyy6/moonbridge/callbacks::call_with" => {
      let a0 = match dec_cb_int_to_int(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_with: bad argument 1",
          )
      }
      let a1 = match dec_int(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "gyyyy6/moonbridge/callbacks::call_with: bad argument 2",
          )
      }
      let value = @callbacks.call_with(a0, a1)
      @abi.Ok(enc_int(Some(value)))
    }
    "abi.release" =>
      match arg(argv, 0) {
        Some(v) =>
          match v.as_list() {
            Some(items) => release_pairs(items)
            None => @abi.Failed("abi.release expects a list")
          }
        None => @abi.Ok(@abi.Int(0))
      }
    "abi.live" => @abi.Ok(@abi.Int(live_total()))
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
