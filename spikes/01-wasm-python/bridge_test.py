"""Spike 01: call a MoonBit(Wasm) module from Python.

Proves the five things MoonBridge needs before it can exist:

  1. plain call ABI          -- i32 in / i32 out
  2. memory export           -- host sees the same linear memory
  3. host -> MoonBit bytes   -- host writes, MoonBit reads
  4. MoonBit -> host bytes   -- MoonBit writes, host reads
  5. UTF-8 string round trip -- multi-byte payload survives both directions

The object-data offset is *discovered at runtime* by scanning for a fingerprint
instead of hard-coding compiler internals. A real generator would pin this per
toolchain version and verify it on every start.

Usage: python bridge_test.py [path/to/module.wasm]
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

from wasmtime import Config, Engine, Instance, Module, Store

DEFAULT_WASM = Path(__file__).parent / "hello/_build/wasm/debug/build/moonbridge-spike.wasm"
PROBE_MARKER = b"MOONBRIDGE-PROBE-0123456789"


def load(path: Path):
    engine = Engine(Config())
    module = Module.from_file(engine, str(path))
    store = Store(engine)
    instance = Instance(store, module, [])
    return store, instance.exports(store)


def find_data_offset(store, exports) -> int:
    """Locate the payload of a Bytes object relative to the object pointer."""
    memory = exports["memory"]
    buf_len = exports["mb_buf_len"]
    probe_ptr = exports["mb_probe"](store)
    probe_len = buf_len(store, probe_ptr)
    if probe_len != len(PROBE_MARKER):
        raise AssertionError(f"probe length {probe_len} != {len(PROBE_MARKER)}")

    window_start = max(0, probe_ptr - 64)
    window = memory.read(store, window_start, window_start + 256)
    idx = window.find(PROBE_MARKER)
    if idx < 0:
        raise AssertionError("probe payload not found near object pointer")
    return window_start + idx - probe_ptr


def benchmark(fn, store, n: int = 200_000) -> float:
    """Aggregate timing: one timer pair around the whole loop."""
    for _ in range(1_000):  # warm up
        fn(store, 1, 2)
    t0 = time.perf_counter_ns()
    for _ in range(n):
        fn(store, 1, 2)
    return (time.perf_counter_ns() - t0) / n


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_WASM
    store, exports = load(path)
    mem = exports["memory"]

    print(f"module : {path}")
    print(f"exports: {sorted(exports.keys())}" if hasattr(exports, "keys") else "")
    print()

    # 1. plain ABI
    add, fib = exports["mb_add"], exports["mb_fib"]
    assert add(store, 2, 40) == 42
    assert fib(store, 20) == 6765
    print("1. call ABI            : mb_add(2,40)=42, mb_fib(20)=6765  OK")

    # 2. layout discovery
    off = find_data_offset(store, exports)
    print(f"2. object data offset  : ptr+{off}  (discovered, not assumed)  OK")

    # 3. host -> MoonBit bytes
    buf_new, buf_len, buf_checksum = (
        exports["mb_buf_new"],
        exports["mb_buf_len"],
        exports["mb_buf_checksum"],
    )
    payload = b"hello moonbridge"
    buf = buf_new(store, len(payload))
    assert buf_len(store, buf) == len(payload)
    mem.write(store, payload, buf + off)
    checksum = buf_checksum(store, buf)
    assert checksum == sum(payload), (checksum, sum(payload))
    print(f"3. host -> MoonBit     : wrote {len(payload)}B, MoonBit sum={checksum}  OK")

    # 4. MoonBit -> host bytes
    filled = exports["mb_buf_filled"](store, 8, 0x41)
    got = bytes(mem.read(store, filled + off, filled + off + 8))
    assert got == b"A" * 8, got
    print(f"4. MoonBit -> host     : read back {got!r}  OK")

    # 5. UTF-8 string round trip
    text = "你好, MoonBit 🚀"
    raw = text.encode("utf-8")
    sbuf = buf_new(store, len(raw))
    mem.write(store, raw, sbuf + off)
    s = exports["mb_string_from_buf"](store, sbuf)
    chars = exports["mb_string_chars"](store, s)
    assert chars == len(text), (chars, len(text))
    out = exports["mb_string_to_buf"](store, s)
    back = bytes(mem.read(store, out + off, out + off + len(raw)))
    assert back == raw, (back, raw)
    print(f"5. UTF-8 round trip    : {chars} code points, {len(raw)}B, byte-identical  OK")

    # 6. call overhead (aggregate, function handle cached)
    ns = benchmark(add, store)
    print(f"6. call overhead       : {ns:.0f} ns/call  (200k calls, handle cached)")
    print(f"   -> ~{1e9 / ns / 1e6:.2f} M calls/s")

    print("\nRESULT: minimal closure established.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
