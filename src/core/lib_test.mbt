///|
test "abi version is pinned" {
  assert_eq(@core.abi_version, 1)
}

///|
test "handle round trip" {
  for i = 0; i < 8; i = i + 1 {
    let raw = @core.encode_handle(i)
    assert_eq(@core.decode_handle(raw), Some(i))
  }
}

///|
test "reserved handle is not a valid index" {
  assert_eq(@core.encode_handle(-1), @core.handle_none)
  assert_eq(@core.decode_handle(@core.handle_none), None)
}
