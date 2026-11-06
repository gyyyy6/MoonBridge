"""Cross-language call benchmark: throughput, memory curve, and a leak check.

The point is not a hero number. It is that a generated binding is worth
shipping only if a hundred thousand calls through it cost what the wire format
says they cost, and leave nothing behind.

Three cases, from the floor up:

``echo``    the protocol and nothing else: decode one value, encode it back.
``valid``   a real string in, a real bool out, no object lifetime at all.
``parse``   a real document, a handle out, released again. This is the case
            where a leak would show up.
``parse/gc`` the same, with the release left to ``weakref.finalize`` and the
            batched collector instead of an explicit ``close()``.

Usage:
    python bench/bench.py --package _gen --wasm _build/wasm/release/build/guest_json/guest_json.wasm

The last section asserts. A non-zero exit code means the boundary leaked.
"""

from __future__ import annotations

import argparse
import gc
import statistics
import sys
import time
from pathlib import Path
from typing import Callable, NamedTuple

DOC = '{"name": "moonbridge", "tags": ["ffi", "codegen"], "count": 3, "ok": true}'
CHECKPOINTS = (1_000, 5_000, 10_000, 25_000, 50_000, 100_000)

#: The garbage-collected case deliberately lets a few wrappers survive the run
#: so that the deferred path is exercised across many batches, not just at the
#: end. They are dropped and re-counted before the final assertion.
SURVIVORS = 5


class Sample(NamedTuple):
    calls: int
    live: int
    memory: int


class Result(NamedTuple):
    name: str
    calls: int
    seconds: float
    median_us: float
    live_end: int
    curve: list[Sample]

    @property
    def per_call_us(self) -> float:
        return self.seconds / self.calls * 1e6


def measure(name: str, calls: int, body: Callable[[int], None]) -> Result:
    """Runs `body(i)` `calls` times and samples the guest at each checkpoint."""
    curve: list[Sample] = []
    stamps: list[float] = []
    live_end = -1
    next_check = 0
    started = time.perf_counter()
    for i in range(calls):
        t0 = time.perf_counter()
        body(i)
        stamps.append(time.perf_counter() - t0)
        if next_check < len(CHECKPOINTS) and i + 1 == CHECKPOINTS[next_check]:
            next_check += 1
            curve.append(
                Sample(i + 1, hook.live_handles(), hook.memory_bytes())
            )
    seconds = time.perf_counter() - started
    # The deferred path only settles after a collection and a flush, so the
    # count that says "nothing was left behind" has to be read afterwards.
    gc.collect()
    hook_rt.flush()
    live_end = hook.live_handles()
    return Result(
        name=name,
        calls=calls,
        seconds=seconds,
        median_us=statistics.median(stamps) * 1e6,
        live_end=live_end,
        curve=curve,
    )


def report(results: list[Result]) -> None:
    print(f"{'case':<10} {'calls':>8} {'total s':>9} {'us/call':>9} {'p50 us':>8}")
    print("-" * 48)
    for r in results:
        print(
            f"{r.name:<10} {r.calls:>8} {r.seconds:>9.3f} "
            f"{r.per_call_us:>9.2f} {r.median_us:>8.2f}"
        )
    print()

    print("memory curve (guest linear memory, KiB)")
    header = "  ".join(f"{s.calls:>8}" for s in results[0].curve)
    print(f"{'case':<10} {header}")
    baseline = results[0].curve[0].memory
    for r in results:
        row = "  ".join(f"{s.memory / 1024:>8.0f}" for s in r.curve)
        print(f"{r.name:<10} {row}")
    print(f"{'base':<10} {baseline / 1024:>8.0f} KiB after the first 1000 calls\n")

    print("live handles at each checkpoint")
    print(f"{'case':<10} {header}")
    for r in results:
        row = "  ".join(f"{s.live:>8}" for s in r.curve)
        print(f"{r.name:<10} {row}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="_gen", help="directory holding the generated package")
    parser.add_argument("--wasm", required=True)
    parser.add_argument("--calls", type=int, default=100_000)
    args = parser.parse_args()

    sys.path.insert(0, str(Path(args.package).resolve()))
    from moonbridge import _runtime, _wasmtime  # noqa: PLC0415
    from moonbridge import moonbitlang__core__json as mjson  # noqa: PLC0415

    global hook, hook_rt
    hook, hook_rt = _wasmtime.open_runtime(Path(args.wasm))
    _runtime.set_default(hook_rt)

    calls = args.calls
    results: list[Result] = []

    results.append(
        measure("echo", calls, lambda i: hook_rt.request("bench.echo", [i]))
    )
    results.append(measure("valid", calls, lambda i: mjson.valid(DOC)))
    results.append(
        measure(
            "parse",
            calls,
            lambda i: mjson.parse(DOC).close(),
        )
    )

    keep: list[object] = []

    def parse_and_drop(i: int) -> None:
        # No `close()`: the wrapper is dropped and `weakref.finalize` queues
        # the id for the batched collector. This is the path a user who never
        # heard of `close()` takes, so it has to be the one that is proven not
        # to leak.
        doc = mjson.parse(DOC)
        if i % 997 == 0:
            keep.append(doc)  # a few deliberately survive, then are dropped
            if len(keep) > SURVIVORS:
                keep.pop(0)

    results.append(measure("parse/gc", calls, parse_and_drop))
    keep.clear()
    gc.collect()
    hook_rt.flush()

    report(results)

    failures = 0

    def check(label: str, ok: bool, detail: str) -> None:
        nonlocal failures
        print(f"{'ok  ' if ok else 'FAIL'} {label}: {detail}")
        if not ok:
            failures += 1

    for r in results:
        expected = SURVIVORS if r.name == "parse/gc" else 0
        check(
            f"{r.name} released everything",
            r.live_end == expected,
            f"live={r.live_end}"
            + (f" ({expected} held on purpose)" if expected else ""),
        )

    final_live = hook.live_handles()
    check("guest is empty at the end", final_live == 0, f"live={final_live}")

    # Wasm memory only grows, so a leak shows up as a curve that keeps
    # climbing. A steady one is the whole claim.
    for r in results:
        last, previous = r.curve[-1], r.curve[-2]
        check(
            f"{r.name} memory plateaus",
            previous.memory == last.memory,
            f"{previous.memory // 1024} KiB -> {last.memory // 1024} KiB "
            f"over the last {last.calls - previous.calls:,} calls",
        )

    print()
    print(f"calls made through the boundary: {hook_rt.calls}")
    print(f"handles released by the batch collector: {hook_rt.releases}")
    print(f"frames per second (valid): {calls / results[1].seconds:,.0f}")

    hook.close()
    hook_rt.close()

    if failures:
        print(f"\n{failures} check(s) failed")
        return 1
    print("\nno leaks: every handle the guest made was released")
    return 0


if __name__ == "__main__":
    sys.exit(main())
