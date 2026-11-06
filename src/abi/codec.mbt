//! The wire format.
//!
//! One `Value` becomes a tagged byte string. The format is little-endian and
//! length-prefixed, and it is intentionally boring: a bridge that is clever on
//! the wire is a bridge nobody can debug from a hex dump.
//!
//! ```text
//!   null    00
//!   true    01          false 02
//!   int     03 <4 bytes LE, two's complement>
//!   double  04 <8 bytes LE, IEEE-754>
//!   string  05 <varint len> <utf-8>
//!   bytes   06 <varint len> <raw>
//!   list    07 <varint count> <value>*
//!   map     08 <varint count> (<value> <value>)*
//!   handle  09 <varint id>
//! ```
//!
//! Lengths are unsigned LEB128 varints. Nothing is padded and nothing is
//! aligned, so a host can decode the payload with a cursor and no allocation
//! strategy.

///|
pub suberror DecodeError {
  DecodeError(String)
} derive(Debug)

///|
const TAG_NULL : Int32 = 0

///|
const TAG_TRUE : Int32 = 1

///|
const TAG_FALSE : Int32 = 2

///|
const TAG_INT : Int32 = 3

///|
const TAG_DOUBLE : Int32 = 4

///|
const TAG_STR : Int32 = 5

///|
const TAG_BYTES : Int32 = 6

///|
const TAG_LIST : Int32 = 7

///|
const TAG_MAP : Int32 = 8

///|
const TAG_HANDLE : Int32 = 9

///|
fn write_varint(buf : @buffer.Buffer, value : Int32) -> Unit {
  let mut x = value
  // A negative length is a bug in the encoder; clamping at zero keeps the
  // stream readable instead of emitting ten 0xFF bytes.
  if x < 0 {
    x = 0
  }
  while x >= 0x80 {
    buf.write_byte(((x & 0x7F) | 0x80).to_byte())
    x = x >> 7
  }
  buf.write_byte(x.to_byte())
}

///|
fn write_value(buf : @buffer.Buffer, value : Value) -> Unit {
  match value {
    Null => buf.write_byte(TAG_NULL.to_byte())
    Bool(true) => buf.write_byte(TAG_TRUE.to_byte())
    Bool(false) => buf.write_byte(TAG_FALSE.to_byte())
    Int(i) => {
      buf.write_byte(TAG_INT.to_byte())
      for shift = 0; shift < 4; shift = shift + 1 {
        buf.write_byte(((i >> (shift * 8)) & 0xFF).to_byte())
      }
    }
    Double(d) => {
      buf.write_byte(TAG_DOUBLE.to_byte())
      buf.write_double_le(d)
    }
    Str(s) => {
      buf.write_byte(TAG_STR.to_byte())
      let raw = @utf8.encode(s)
      write_varint(buf, raw.length())
      buf.write_bytes(raw)
    }
    Bytes(b) => {
      buf.write_byte(TAG_BYTES.to_byte())
      write_varint(buf, b.length())
      buf.write_bytes(b)
    }
    List(items) => {
      buf.write_byte(TAG_LIST.to_byte())
      write_varint(buf, items.length())
      for item in items {
        write_value(buf, item)
      }
    }
    Map(entries) => {
      buf.write_byte(TAG_MAP.to_byte())
      write_varint(buf, entries.length())
      for entry in entries {
        write_value(buf, entry.0)
        write_value(buf, entry.1)
      }
    }
    Handle(id) => {
      buf.write_byte(TAG_HANDLE.to_byte())
      write_varint(buf, id)
    }
  }
}

///|
pub fn encode(value : Value) -> Bytes {
  let buf = @buffer.Buffer()
  write_value(buf, value)
  buf.to_bytes()
}

///|
/// A read cursor over a payload.
priv struct Cursor {
  data : Bytes
  mut pos : Int32
}

///|
fn Cursor::new(data : Bytes) -> Cursor {
  { data, pos: 0, }
}

///|
fn Cursor::byte(self : Cursor) -> Int32 raise DecodeError {
  if self.pos >= self.data.length() {
    raise DecodeError("truncated payload")
  }
  let b = self.data.unsafe_get(self.pos).to_int()
  self.pos = self.pos + 1
  b
}

///|
fn Cursor::varint(self : Cursor) -> Int32 raise DecodeError {
  let mut result = 0
  let mut shift = 0
  while true {
    let b = self.byte()
    result = result | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      break
    }
    shift = shift + 7
    if shift > 28 {
      raise DecodeError("varint too long")
    }
  }
  result
}

///|
fn Cursor::take(self : Cursor, n : Int32) -> Bytes raise DecodeError {
  if n < 0 || self.pos + n > self.data.length() {
    raise DecodeError("truncated payload")
  }
  let out = self.data.exact_view(start=self.pos, end=self.pos + n)
  self.pos = self.pos + n
  @buffer.from_bytes(out).to_bytes()
}

///|
fn Cursor::value(self : Cursor) -> Value raise DecodeError {
  let tag = self.byte()
  match tag {
    TAG_NULL => Null
    TAG_TRUE => Bool(true)
    TAG_FALSE => Bool(false)
    TAG_INT => {
      let mut v = 0
      for shift = 0; shift < 4; shift = shift + 1 {
        v = v | (self.byte() << (shift * 8))
      }
      Int(v)
    }
    TAG_DOUBLE => {
      let raw = self.take(8)
      let bits = bytes_to_int64(raw)
      Double(bits.reinterpret_as_double())
    }
    TAG_STR => {
      let n = self.varint()
      let raw = self.take(n)
      Str(
        @utf8.decode(raw) catch {
          _ => raise DecodeError("invalid utf-8 in string")
        },
      )
    }
    TAG_BYTES => {
      let n = self.varint()
      Bytes(self.take(n))
    }
    TAG_LIST => {
      let n = self.varint()
      let items : Array[Value] = []
      let mut i = 0
      while i < n {
        items.push(self.value())
        i = i + 1
      }
      List(items)
    }
    TAG_MAP => {
      let n = self.varint()
      let entries : Array[(Value, Value)] = []
      let mut i = 0
      while i < n {
        let key = self.value()
        let entry = self.value()
        entries.push((key, entry))
        i = i + 1
      }
      Map(entries)
    }
    TAG_HANDLE => Handle(self.varint())
    _ => raise DecodeError("unknown tag " + tag.to_string())
  }
}

///|
/// Assembles eight little-endian bytes into the bit pattern of a double.
///
/// MoonBit exposes `reinterpret_as_double` on `Int64` but no
/// `from_le_bytes`, so the assembly is explicit rather than clever.
fn bytes_to_int64(raw : Bytes) -> Int64 {
  let mut v : Int64 = 0L
  for i = 0; i < 8; i = i + 1 {
    v = v | (raw.unsafe_get(i).to_int().to_int64() << (i * 8))
  }
  v
}

///|
pub fn decode(data : Bytes) -> Value raise DecodeError {
  let cursor = Cursor::new(data)
  let v = cursor.value()
  if cursor.pos != data.length() {
    // Trailing bytes mean the encoder and decoder disagree about the shape of
    // a value; silently ignoring them would hide a version skew.
    raise DecodeError("trailing bytes after value")
  }
  v
}

///|
/// The outcome of one call, as it travels back to the host.
pub(all) enum Status {
  Ok(Value)
  /// The guest raised a `suberror`; the string is its rendered message.
  Failed(String)
  /// The same, but the guest also knows what it raised.
  ///
  /// The type name is what lets Python raise the generated exception class
  /// instead of a catch-all, so `except ParseError` works. It travels as a map
  /// rather than as a new frame layout: the payload of a failure was always a
  /// `Value`, and a map is a value.
  FailedAs(String, String)
  /// The guest panicked or hit an unreachable state.
  Panicked(String)
} derive(Debug)

///|
const STATUS_OK : Int32 = 0

///|
const STATUS_FAILED : Int32 = 1

///|
const STATUS_PANIC : Int32 = 2

///|
pub fn encode_status(status : Status) -> Bytes {
  let buf = @buffer.Buffer()
  match status {
    Ok(v) => {
      buf.write_byte(STATUS_OK.to_byte())
      write_value(buf, v)
    }
    Failed(message) => {
      buf.write_byte(STATUS_FAILED.to_byte())
      write_value(buf, Str(message))
    }
    FailedAs(kind, message) => {
      buf.write_byte(STATUS_FAILED.to_byte())
      write_value(
        buf,
        Map([(Str("type"), Str(kind)), (Str("message"), Str(message))]),
      )
    }
    Panicked(message) => {
      buf.write_byte(STATUS_PANIC.to_byte())
      write_value(buf, Str(message))
    }
  }
  buf.to_bytes()
}

///|
/// Reads a failure payload, which is either a bare message or a map naming the
/// type. The bare form is what an older guest sends, and accepting both costs
/// one `match`.
fn failure_of(value : Value) -> (String, String)? {
  match value {
    Str(message) => Some(("", message))
    Map(pairs) => {
      let mut kind = ""
      let mut message = ""
      let mut ok = true
      for pair in pairs {
        let (key, item) = pair
        match (key.as_string(), item.as_string()) {
          (Some("type"), Some(v)) => kind = v
          (Some("message"), Some(v)) => message = v
          (Some(_), Some(_)) => ()
          _ => ok = false
        }
      }
      if ok {
        Some((kind, message))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
pub fn decode_status(data : Bytes) -> Status raise DecodeError {
  if data.length() == 0 {
    raise DecodeError("empty response")
  }
  let cursor = Cursor::new(data)
  let tag = cursor.byte()
  let payload = cursor.value()
  match tag {
    STATUS_OK => Ok(payload)
    STATUS_FAILED =>
      match failure_of(payload) {
        // A guest that only knows the message keeps the old shape, so the
        // typed form is an addition rather than a break.
        Some(("", message)) => Failed(message)
        Some((kind, message)) => FailedAs(kind, message)
        None => raise DecodeError("failure without a message")
      }
    STATUS_PANIC =>
      match payload.as_string() {
        Some(message) => Panicked(message)
        None => raise DecodeError("panic without a message")
      }
    _ => raise DecodeError("unknown status " + tag.to_string())
  }
}
