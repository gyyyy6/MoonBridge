//! The handle table, including the failure modes that make it worth having.

///|
test "insert then get returns the same value" {
  let t : @abi.HandleTable[String] = @abi.HandleTable::new()
  let id = t.insert("hello")
  assert_eq(t.get(id), Some("hello"))
  assert_eq(t.live_count(), 1)
}

///|
test "ids are unique and independent" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  let a = t.insert(1)
  let b = t.insert(2)
  assert_true(a != b)
  assert_eq(t.get(a), Some(1))
  assert_eq(t.get(b), Some(2))
  assert_eq(t.live_count(), 2)
}

///|
test "a released handle stops resolving" {
  let t : @abi.HandleTable[String] = @abi.HandleTable::new()
  let id = t.insert("gone")
  assert_true(t.release(id))
  assert_eq(t.get(id), None)
  assert_eq(t.live_count(), 0)
  // Releasing twice is a bug in the host, and it must be reported as one.
  assert_false(t.release(id))
}

///|
test "a recycled slot does not resurrect the old handle" {
  // This is the whole reason ids carry a generation. Without it, the id just
  // released would address whatever took its place, and the caller would read
  // a completely unrelated value with no error at all.
  let t : @abi.HandleTable[String] = @abi.HandleTable::new()
  let first = t.insert("first")
  ignore(t.release(first))
  let second = t.insert("second")
  // Same slot, so the numeric slot index matches but the id does not.
  assert_eq(first >> 10, second >> 10)
  assert_true(first != second)
  assert_eq(t.get(first), None)
  assert_eq(t.get(second), Some("second"))
}

///|
test "garbage ids are refused without panicking" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  ignore(t.insert(1))
  assert_eq(t.get(1 << 20), None)
  assert_eq(t.get(-1), None)
  assert_false(t.release(99999))
}

///|
test "resolve reports an unknown handle instead of returning nothing" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  let raised = try {
    ignore(t.resolve(12345))
    false
  } catch {
    @abi.UnknownHandle(_) => true
    _ => false
  }
  assert_true(raised)
}

///|
test "release_all empties the table but keeps it usable" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  let a = t.insert(1)
  let b = t.insert(2)
  t.release_all()
  assert_eq(t.live_count(), 0)
  assert_eq(t.get(a), None)
  assert_eq(t.get(b), None)
  // The instance is torn down and rebuilt in the same process during tests, so
  // the table must not be poisoned by the reset.
  let c = t.insert(3)
  assert_eq(t.get(c), Some(3))
}

///|
test "the table grows past its initial slots and keeps working" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  let ids : Array[Int32] = []
  for i = 0; i < 500; i = i + 1 {
    ids.push(t.insert(i))
  }
  assert_eq(t.live_count(), 500)
  let mut ok = true
  for i = 0; i < 500; i = i + 1 {
    if t.get(ids[i]) != Some(i) {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "a free slot is reused before the table grows" {
  let t : @abi.HandleTable[Int32] = @abi.HandleTable::new()
  let a = t.insert(1)
  let _b = t.insert(2)
  ignore(t.release(a))
  let capacity = t.capacity()
  ignore(t.insert(3))
  // Reuse, not growth: a long-lived session that creates and drops objects
  // must not grow the table without bound.
  assert_eq(t.capacity(), capacity)
  assert_eq(t.live_count(), 2)
}
