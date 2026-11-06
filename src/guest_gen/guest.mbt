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
  builtin_Json : @abi.HandleTable[@ref.Ref[@builtin.Json]]
  json_JsonDecodeError : @abi.HandleTable[@ref.Ref[@json.JsonDecodeError]]
  json_ParseError : @abi.HandleTable[@ref.Ref[@json.ParseError]]
  json_JsonPath : @abi.HandleTable[@ref.Ref[@json.JsonPath]]
  json_Position : @abi.HandleTable[@ref.Ref[@json.Position]]
  json_Replacer : @abi.HandleTable[@ref.Ref[@json.Replacer]]
  builtin_Failure : @abi.HandleTable[@ref.Ref[@builtin.Failure]]
  builtin_ArgsLoc : @abi.HandleTable[@ref.Ref[@builtin.ArgsLoc]]
  builtin_Hasher : @abi.HandleTable[@ref.Ref[@builtin.Hasher]]
  builtin_SourceLoc : @abi.HandleTable[@ref.Ref[@builtin.SourceLoc]]
  builtin_StringBuilder : @abi.HandleTable[@ref.Ref[@builtin.StringBuilder]]
  lexbuf_Lexbuf : @abi.HandleTable[@ref.Ref[@lexbuf.Lexbuf]]
  lexbuf_StringScanner : @abi.HandleTable[@ref.Ref[@lexbuf.StringScanner]]
}

///|
let tables : Tables = {
  builtin_Json: @abi.HandleTable::new(),
  json_JsonDecodeError: @abi.HandleTable::new(),
  json_ParseError: @abi.HandleTable::new(),
  json_JsonPath: @abi.HandleTable::new(),
  json_Position: @abi.HandleTable::new(),
  json_Replacer: @abi.HandleTable::new(),
  builtin_Failure: @abi.HandleTable::new(),
  builtin_ArgsLoc: @abi.HandleTable::new(),
  builtin_Hasher: @abi.HandleTable::new(),
  builtin_SourceLoc: @abi.HandleTable::new(),
  builtin_StringBuilder: @abi.HandleTable::new(),
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
/// A handle from the host, resolved against the table for `@builtin.Json`.
fn dec_builtin_Json(v : @abi.Value?) -> @builtin.Json? {
  match v {
    Some(x) =>
      match x.as_handle() {
        Some(id) =>
          match tables.builtin_Json.get(id) {
            Some(slot) => Some(slot.val)
            None => None
          }
        None => None
      }
    None => None
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
fn dec_arr_builtin_Json(v : @abi.Value?) -> Array[@builtin.Json]? {
  match v {
    Some(@abi.List(items)) => {
      let out : Array[@builtin.Json] = []
      let mut ok = true
      for item in items {
        match dec_builtin_Json(Some(item)) {
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
fn dec_map_str_builtin_Json(v : @abi.Value?) -> Map[String, @builtin.Json]? {
  match v {
    Some(@abi.Map(pairs)) => {
      let out : Map[String, @builtin.Json] = Map([])
      let mut ok = true
      for pair in pairs {
        let (raw_key, raw_value) = pair
        match (dec_str(Some(raw_key)), dec_builtin_Json(Some(raw_value))) {
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
fn enc_builtin_Json(v : @builtin.Json?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Json.insert(@ref.Ref(x)))
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
fn enc_builtin_Hasher(v : @builtin.Hasher?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_Hasher.insert(@ref.Ref(x)))
    None => @abi.Value::unit()
  }
}

///|
fn enc_builtin_StringBuilder(v : @builtin.StringBuilder?) -> @abi.Value raise {
  match v {
    Some(x) => @abi.Handle(tables.builtin_StringBuilder.insert(@ref.Ref(x)))
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
fn enc_strview(v : StringView?) -> @abi.Value {
  match v {
    Some(x) => @abi.Str(x.to_owned())
    None => @abi.Value::unit()
  }
}

///|
/// Objects the tables still hold.
fn live_total() -> Int32 {
  tables.builtin_Json.live_count() +
  tables.json_JsonDecodeError.live_count() +
  tables.json_ParseError.live_count() +
  tables.json_JsonPath.live_count() +
  tables.json_Position.live_count() +
  tables.json_Replacer.live_count() +
  tables.builtin_Failure.live_count() +
  tables.builtin_ArgsLoc.live_count() +
  tables.builtin_Hasher.live_count() +
  tables.builtin_SourceLoc.live_count() +
  tables.builtin_StringBuilder.live_count() +
  tables.lexbuf_Lexbuf.live_count() +
  tables.lexbuf_StringScanner.live_count()
}

///|
/// Releases one id from the table its tag names. The tag exists because an id
/// is only unique within one table.
fn release_tag(tag : Int32, id : Int32) -> Bool {
  match tag {
    1 => tables.builtin_Json.release(id)
    2 => tables.json_JsonDecodeError.release(id)
    3 => tables.json_ParseError.release(id)
    4 => tables.json_JsonPath.release(id)
    5 => tables.json_Position.release(id)
    6 => tables.json_Replacer.release(id)
    7 => tables.builtin_Failure.release(id)
    8 => tables.builtin_ArgsLoc.release(id)
    9 => tables.builtin_Hasher.release(id)
    10 => tables.builtin_SourceLoc.release(id)
    11 => tables.builtin_StringBuilder.release(id)
    12 => tables.lexbuf_Lexbuf.release(id)
    13 => tables.lexbuf_StringScanner.release(id)
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
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
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
    "moonbitlang/core/json::Json::stringify" => {
      let a0 = match dec_builtin_Json(arg(argv, 0)) {
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
                  @builtin.Json::stringify(
                    a0,
                    escape_slash=v1,
                    indent=v2,
                    replacer=v3,
                  )
                None => @builtin.Json::stringify(a0, escape_slash=v1, indent=v2)
              }
            None =>
              match a3 {
                Some(v3) =>
                  @builtin.Json::stringify(a0, escape_slash=v1, replacer=v3)
                None => @builtin.Json::stringify(a0, escape_slash=v1)
              }
          }
        None =>
          match a2 {
            Some(v2) =>
              match a3 {
                Some(v3) => @builtin.Json::stringify(a0, indent=v2, replacer=v3)
                None => @builtin.Json::stringify(a0, indent=v2)
              }
            None =>
              match a3 {
                Some(v3) => @builtin.Json::stringify(a0, replacer=v3)
                None => @builtin.Json::stringify(a0)
              }
          }
      }
      @abi.Ok(enc_str(Some(value)))
    }
    "moonbitlang/core/json::Json::transform" => {
      let a0 = match dec_builtin_Json(arg(argv, 0)) {
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
      let value = @builtin.Json::transform(a0, a1)
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
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
    "moonbitlang/core/builtin::Hasher::Hasher" => {
      let a0 = dec_int(arg(argv, 0))
      let value = match a0 {
        Some(v0) => @builtin.Hasher::Hasher(seed=v0)
        None => @builtin.Hasher::Hasher()
      }
      @abi.Ok(enc_builtin_Hasher(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
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
    "moonbitlang/core/builtin::Json::array" => {
      let a0 = match dec_arr_builtin_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::array: bad argument 1",
          )
      }
      let value = @builtin.Json::array(a0)
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::boolean" => {
      let a0 = match dec_bool(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::boolean: bad argument 1",
          )
      }
      let value = @builtin.Json::boolean(a0)
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::empty_object" => {
      let value = @builtin.Json::empty_object()
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::equal" => {
      let a0 = match dec_builtin_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::equal: bad argument 1",
          )
      }
      let a1 = match dec_builtin_Json(arg(argv, 1)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::equal: bad argument 2",
          )
      }
      let value = @builtin.Json::equal(a0, a1)
      @abi.Ok(enc_bool(Some(value)))
    }
    "moonbitlang/core/builtin::Json::null" => {
      let value = @builtin.Json::null()
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::number" => {
      let a0 = match dec_double(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::number: bad argument 1",
          )
      }
      let a1 = dec_str(arg(argv, 1))
      let value = match a1 {
        Some(v1) => @builtin.Json::number(a0, repr=v1)
        None => @builtin.Json::number(a0)
      }
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::object" => {
      let a0 = match dec_map_str_builtin_Json(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::object: bad argument 1",
          )
      }
      let value = @builtin.Json::object(a0)
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
    }
    "moonbitlang/core/builtin::Json::string" => {
      let a0 = match dec_str(arg(argv, 0)) {
        Some(v) => v
        None =>
          return @abi.Failed(
            "moonbitlang/core/builtin::Json::string: bad argument 1",
          )
      }
      let value = @builtin.Json::string(a0)
      @abi.Ok(enc_builtin_Json(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
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
    "moonbitlang/core/builtin::StringBuilder::StringBuilder" => {
      let a0 = dec_int(arg(argv, 0))
      let value = match a0 {
        Some(v0) => @builtin.StringBuilder::StringBuilder(size_hint=v0)
        None => @builtin.StringBuilder::StringBuilder()
      }
      @abi.Ok(enc_builtin_StringBuilder(Some(value))) catch {
        error => @abi.Failed(error.to_string())
      }
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
      let value = @builtin.StringBuilder::reset(a0)
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
