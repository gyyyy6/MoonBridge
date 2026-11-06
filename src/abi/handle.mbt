//! The guest half of the handle protocol.
//!
//! A handle is an integer that stands for a MoonBit object which stayed in the
//! guest's heap. The host passes the integer back in later calls, and the guest
//! turns it into the object again. Two things make that safe:
//!
//! **The table owns the value.** While a handle exists, the table holds a
//! reference to the object, so the MoonBit runtime cannot collect it. Releasing
//! the handle drops that reference, and only then may the value go away.
//!
//! **Every id carries a generation.** A released slot is reused, and without a
//! generation counter a stale id would silently address whatever took its
//! place — the classic dangling-handle bug, arriving as wrong data instead of a
//! crash. The counter makes the stale id fail to resolve, which the host turns
//! into an explicit error.
//!
//! The table is generic rather than dynamically typed because MoonBit has no
//! runtime type information to downcast with. A guest is generated per module,
//! so one `HandleTable[Json]` per module is exactly the right granularity.
//!
//! ```text
//!   id = (slot << 10) | generation,  generation >= 1
//! ```
//!
//! Ten bits of generation covers 1024 releases per slot, and 20 bits of slot
//! covers a million live objects — far past what a Python caller will hold
//! before the table is asked to grow instead. Generation 0 is reserved: a
//! handle of 0 has to mean "no object" on the host side, so no live handle may
//! carry it.

///|
/// Bits reserved for the generation counter in a handle id.
const GEN_BITS : Int32 = 10

///|
const GEN_MASK : Int32 = (1 << GEN_BITS) - 1

///|
const MAX_SLOTS : Int32 = 1 << 20

///|
pub(all) struct HandleTable[T] {
  /// Object per slot. `None` means the slot is free.
  slots : Array[T?]
  /// Release counter per slot; bumped every time the slot is freed.
  gens : Array[Int32]
  /// Free slot indices, reused before the table grows.
  free : Array[Int32]
  /// Objects currently held. This is the number the leak test watches.
  mut live : Int32
  /// Slots whose generation counter ran out and will never be reused.
  mut retired : Int32
}

///|
pub fn[T] HandleTable::new() -> HandleTable[T] {
  { slots: [], gens: [], free: [], live: 0, retired: 0, }
}

///|
/// Stores `value` and returns its handle id.
pub fn[T] HandleTable::insert(
  self : HandleTable[T],
  value : T,
) -> Int32 raise HandleError {
  match self.free.pop() {
    Some(slot) => {
      // The slot already has a generation: its old handle is dead by
      // construction, because a slot only reaches the free list on release.
      self.slots[slot] = Some(value)
      self.live = self.live + 1
      (slot << GEN_BITS) | self.gens[slot]
    }
    None => {
      let slot = self.slots.length()
      if slot >= MAX_SLOTS {
        raise HandleTableFull(MAX_SLOTS)
      }
      self.slots.push(Some(value))
      // The first handle to a slot is generation 1, never 0: the host reads a
      // handle of 0 as "no object", so id 0 must not exist.
      self.gens.push(1)
      self.live = self.live + 1
      (slot << GEN_BITS) | 1
    }
  }
}

///|
/// The object behind a handle, or `None` when the handle was released or never
/// existed.
pub fn[T] HandleTable::get(self : HandleTable[T], id : Int32) -> T? {
  let slot = id >> GEN_BITS
  let gen = id & GEN_MASK
  if slot < 0 || slot >= self.slots.length() {
    return None
  }
  if self.gen_at(slot) != gen {
    return None
  }
  self.slots[slot]
}

///|
fn[T] HandleTable::gen_at(self : HandleTable[T], slot : Int32) -> Int32 {
  self.gens[slot]
}

///|
/// Drops the reference behind a handle. Returns `false` when the handle was
/// already released, which the host treats as a double free.
pub fn[T] HandleTable::release(self : HandleTable[T], id : Int32) -> Bool {
  let slot = id >> GEN_BITS
  let gen = id & GEN_MASK
  if slot < 0 || slot >= self.slots.length() {
    return false
  }
  if self.gen_at(slot) != gen {
    return false
  }
  match self.slots[slot] {
    None => false
    Some(_) => {
      self.slots[slot] = None
      // Bumping the generation is what makes the id just released, and every
      // earlier handle to that slot, fail to resolve from now on.
      self.bump(slot)
      self.live = self.live - 1
      true
    }
  }
}

///|
/// Advances a slot's generation, or retires the slot when it has served
/// `GEN_MASK` lifetimes.
///
/// Wrapping the counter would put generation 0 back on the table, and for slot
/// 0 that is handle id 0 — the value the host reads as "no object", where it
/// skips the finalizer and returns from `close()` before releasing anything.
/// The benchmark found it exactly: one document leaked out of every 1023, and
/// the leak looked like a bug in `close()`.
///
/// Retiring the slot instead costs one 8-byte slot per 1023 objects that pass
/// through the same slot, which is nothing next to silently dropping a release.
fn[T] HandleTable::bump(self : HandleTable[T], slot : Int32) -> Unit {
  let next = self.gen_at(slot) + 1
  if next > GEN_MASK {
    // Stay at the last generation and never hand the slot out again: any id
    // that could still resolve to it is one this table has already retired.
    self.retired = self.retired + 1
  } else {
    self.gens[slot] = next
    self.free.push(slot)
  }
}

///|
/// Releases every handle. Used when the host tears the instance down.
pub fn[T] HandleTable::release_all(self : HandleTable[T]) -> Unit {
  let mut slot = 0
  while slot < self.slots.length() {
    match self.slots[slot] {
      // An empty slot has nothing to release, and bumping it again would
      // retire it early.
      None => ()
      Some(_) => {
        self.slots[slot] = None
        self.bump(slot)
      }
    }
    slot = slot + 1
  }
  self.live = 0
}

///|
pub fn[T] HandleTable::live_count(self : HandleTable[T]) -> Int32 {
  self.live
}

///|
/// Slots that can never be handed out again. Non-zero only after a slot has
/// served a thousand lifetimes, which is worth reporting rather than hiding.
pub fn[T] HandleTable::retired_count(self : HandleTable[T]) -> Int32 {
  self.retired
}

///|
/// Slots allocated so far, including free ones. Grows monotonically.
pub fn[T] HandleTable::capacity(self : HandleTable[T]) -> Int32 {
  self.slots.length()
}

///|
/// A handle that cannot be resolved. Raised instead of returning a wrong value.
pub suberror HandleError {
  HandleTableFull(Int32)
  UnknownHandle(Int32)
} derive(Debug)

///|
/// Like `get`, but reports a protocol error instead of `None`.
pub fn[T] HandleTable::resolve(
  self : HandleTable[T],
  id : Int32,
) -> T raise HandleError {
  match self.get(id) {
    Some(value) => value
    None => raise UnknownHandle(id)
  }
}
