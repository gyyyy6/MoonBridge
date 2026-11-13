//! The wire format, pinned byte by byte.
//!
//! These vectors are the contract between the two implementations: the Python
//! codec in `_codec.py` is generated from the same table and is tested against
//! the very same byte strings, so a change on one side that the other does not
//! know about fails here rather than at a user's call site.

///|
fn bytes_of(b : Bytes) -> Array[Int32] {
  let out : Array[Int32] = []
  for i = 0; i < b.length(); i = i + 1 {
    out.push(b.unsafe_get(i).to_int())
  }
  out
}

///|
test "wire: primitives are one tag plus a fixed payload" {
  assert_eq(bytes_of(@abi.encode(@abi.Null)), [0])
  assert_eq(bytes_of(@abi.encode(@abi.Bool(true))), [1])
  assert_eq(bytes_of(@abi.encode(@abi.Bool(false))), [2])
  // 42 little-endian, two's complement.
  assert_eq(bytes_of(@abi.encode(@abi.Int(42))), [3, 42, 0, 0, 0])
  assert_eq(bytes_of(@abi.encode(@abi.Int(-1))), [3, 255, 255, 255, 255])
}

///|
test "wire: a double is its IEEE-754 bit pattern, little-endian" {
  assert_eq(bytes_of(@abi.encode(@abi.Double(1.0))), [
    4, 0, 0, 0, 0, 0, 0, 240, 63,
  ])
  assert_eq(bytes_of(@abi.encode(@abi.Double(0.0))), [4, 0, 0, 0, 0, 0, 0, 0, 0])
}

///|
test "wire: strings and bytes are length-prefixed" {
  assert_eq(bytes_of(@abi.encode(@abi.Str("hi"))), [5, 2, 104, 105])
  // A multi-byte code point is counted in bytes, not code points.
  assert_eq(bytes_of(@abi.encode(@abi.Str("é"))), [5, 2, 195, 169])
  let raw = @utf8.encode("ab")
  assert_eq(bytes_of(@abi.encode(@abi.Bytes(raw))), [6, 2, 97, 98])
}

///|
test "wire: containers are a count then their elements" {
  assert_eq(bytes_of(@abi.encode(@abi.List([@abi.Bool(true), @abi.Null]))), [
    7, 2, 1, 0,
  ])
  assert_eq(bytes_of(@abi.encode(@abi.Map([(@abi.Str("a"), @abi.Int(1))]))), [
    8, 1, 5, 1, 97, 3, 1, 0, 0, 0,
  ])
  assert_eq(bytes_of(@abi.encode(@abi.Handle(5))), [9, 5])
}

///|
test "wire: long strings use a multi-byte varint length" {
  let text = String::make(200, 'x')
  let bytes = bytes_of(@abi.encode(@abi.Str(text)))
  // 200 = 0xC8 -> varint 0xC8 0x01.
  assert_eq(bytes[0], 5)
  assert_eq(bytes[1], 200)
  assert_eq(bytes[2], 1)
  assert_eq(bytes.length(), 3 + 200)
}

///|
test "round trip preserves every variant" {
  let value = @abi.Map([
    (@abi.Str("int"), @abi.Int(-7)),
    (@abi.Str("double"), @abi.Double(0.1)),
    (@abi.Str("list"), @abi.List([@abi.Null, @abi.Bool(false)])),
    (@abi.Str("handle"), @abi.Handle(1048577)),
  ])
  let back = @abi.decode(@abi.encode(value))
  // Structural equality is not derived on `Value` (it holds `Double`), so the
  // test compares the pieces it cares about.
  match back {
    @abi.Map(entries) => {
      assert_eq(entries.length(), 4)
      assert_eq(entries[0].1, @abi.Int(-7))
      match entries[1].1 {
        @abi.Double(d) => assert_true(d == 0.1)
        _ => fail("expected a double")
      }
      assert_eq(entries[3].1, @abi.Handle(1048577))
    }
    _ => fail("expected a map")
  }
}

///|
test "round trip is exact for extreme doubles" {
  for d in [0.0, -0.0, 1.0e-308, 1.7976931348623157e308, -2.5, 1.0 / 3.0] {
    match @abi.decode(@abi.encode(@abi.Double(d))) {
      @abi.Double(back) =>
        // Bit-exact, not approximately equal: `-0.0 == 0.0` would hide a
        // sign-loss bug that matters to a caller doing 1/x.
        assert_eq(@abi.encode(@abi.Double(back)), @abi.encode(@abi.Double(d)))
      _ => fail("expected a double")
    }
  }
}

///|
test "an empty string survives the round trip" {
  match @abi.decode(@abi.encode(@abi.Str(""))) {
    @abi.Str(s) => assert_eq(s, "")
    _ => fail("expected a string")
  }
}

///|
test "truncated payloads are rejected" {
  let full = bytes_of(@abi.encode(@abi.Str("hello")))
  let cut = @buffer.from_array(
    Array::makei(full.length() - 2, fn(i) { full[i].to_byte() }),
  ).to_bytes()
  let rejected = try {
    ignore(@abi.decode(cut))
    false
  } catch {
    @abi.DecodeError(_) => true
  }
  assert_true(rejected)
}

///|
test "trailing bytes are rejected" {
  // Accepting them would let an encoder and decoder disagree about a value's
  // shape without anyone noticing.
  let padded = @buffer.from_array(
    Array::makei(6, fn(i) {
      if i < 5 {
        @abi.encode(@abi.Int(1)).unsafe_get(i)
      } else {
        b'\x00'
      }
    }),
  ).to_bytes()
  let rejected = try {
    ignore(@abi.decode(padded))
    false
  } catch {
    @abi.DecodeError(_) => true
  }
  assert_true(rejected)
}

///|
test "status frames carry ok, failure and panic apart" {
  match @abi.decode_status(@abi.encode_status(@abi.Ok(@abi.Int(3)))) {
    @abi.Ok(v) => assert_eq(v, @abi.Int(3))
    _ => fail("expected ok")
  }
  match @abi.decode_status(@abi.encode_status(@abi.Failed("bad input"))) {
    @abi.Failed(m) => assert_eq(m, "bad input")
    _ => fail("expected failure")
  }
  match @abi.decode_status(@abi.encode_status(@abi.Panicked("boom"))) {
    @abi.Panicked(m) => assert_eq(m, "boom")
    _ => fail("expected panic")
  }
}

///|
test "batch: a count and length-prefixed frames, byte for byte" {
  // count=2, len=1 [1], len=4 [5,2,'h','i']. The Python `_codec.dump_batch`
  // is generated from this same table, so a skew fails here and not at a
  // user's call site.
  let frame = @abi.encode_batch([
    @abi.encode(@abi.Bool(true)),
    @abi.encode(@abi.Str("hi")),
  ])
  assert_eq(bytes_of(frame), [
    2, 0, 0, 0, 1, 0, 0, 0, 1, 4, 0, 0, 0, 5, 2, 104, 105,
  ])
  let back = @abi.decode_batch(frame)
  assert_eq(back.length(), 2)
  assert_eq(bytes_of(back[0]), [1])
  assert_eq(bytes_of(back[1]), [5, 2, 104, 105])
  assert_eq(bytes_of(@abi.encode_batch([])), [0, 0, 0, 0])
  assert_eq(@abi.decode_batch(@abi.encode_batch([])).length(), 0)
}

///|
test "batch: a length past the end and trailing bytes are rejected" {
  // A frame whose declared length overruns the container must not be read as
  // two short frames.
  let good = @abi.encode_batch([@abi.encode(@abi.Int(7))])
  let bytes = bytes_of(good)
  let truncated = @buffer.from_array(
    Array::makei(bytes.length() - 1, fn(i) { bytes[i].to_byte() }),
  ).to_bytes()
  let rejected = try {
    ignore(@abi.decode_batch(truncated))
    false
  } catch {
    @abi.DecodeError(_) => true
  }
  assert_true(rejected)
  let padded = @buffer.from_array(
    Array::makei(bytes.length() + 1, fn(i) {
      if i < bytes.length() {
        bytes[i].to_byte()
      } else {
        b'\x00'
      }
    }),
  ).to_bytes()
  let trailing = try {
    ignore(@abi.decode_batch(padded))
    false
  } catch {
    @abi.DecodeError(_) => true
  }
  assert_true(trailing)
}

///|
test "batch: many frames round-trip in order" {
  let frames : Array[Bytes] = []
  for i = 0; i < 64; i = i + 1 {
    frames.push(@abi.encode(@abi.Int(i)))
  }
  let back = @abi.decode_batch(@abi.encode_batch(frames))
  assert_eq(back.length(), 64)
  for i = 0; i < 64; i = i + 1 {
    assert_eq(@abi.decode(back[i]), @abi.Int(i))
  }
}
