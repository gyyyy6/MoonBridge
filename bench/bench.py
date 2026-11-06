"""Cross-language call benchmark: throughput, memory curve, and a leak check.

The point is not a hero number. It is that a generated binding is worth
shipping only if a hundred thousand calls through it cost what the wire format
says they cost, and leave nothing behind.

Three cases, from the floor up:

``valid``   a real string in, a real bool out, no object lifetime at all. The
            floor: one frame, no handle.
``parse``   a real document, a handle out, released again. This is the case
            where a leak would show up.
``parse/gc`` the same, with the release left to ``weakref.finalize`` and the
            batched collector instead of an explicit ``close()``.

And three that exercise the S4 object model, where one "iteration" is several
calls because the object is built and then read:

``ctor+field``  construct a `Position`, read both fields, release it.
``ctor/gc``     the same, with the release deferred to the collector.
``setter``      construct a `StringScanner`, write `cursor`, read it back.

Usage:
    python bench/bench.py --package _gen --wasm _build/wasm/release/build/guest_gen/guest_gen.wasm

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
TEXT = "hello world"
CHECKPOINTS = (1_000, 5_000, 10_000, 25_000, 50_000, 100_000)

#: Replaced by `main()` with a set scaled to `--calls`. The plateau assertion
#: compares the last two samples, so even a short run needs two of them.
POINTS: tuple[int, ...] = ()

#: The garbage-collected case deliberately lets a few wrappers survive the run
#: so that the deferred path is exercised across many batches, not just at the
#: end. They are dropped and re-counted before the final assertion.
SURVIVORS = 5


def checkpoints_for(calls: int) -> tuple[int, ...]:
    """Scales the fixed sample points down to a short run.

    The last sample is always the end of the run, and a midpoint is added when
    the fixed points would leave fewer than two samples to compare.
    """
    points = [p for p in CHECKPOINTS if p < calls]
    if calls >= 2 and (not points or points[-1] < calls // 2):
        points.append(calls // 2)
    points.append(calls)
    return tuple(dict.fromkeys(p for p in points if 0 < p <= calls))


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
        if next_check < len(POINTS) and i + 1 == POINTS[next_check]:
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
    print(f"{'base':<10} {baseline / 1024:>8.0f} KiB after the first checkpoint\n")

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
    from moonbridge import moonbitlang__core__lexbuf as mlex  # noqa: PLC0415

    global hook, hook_rt, POINTS
    hook, hook_rt = _wasmtime.open_runtime(Path(args.wasm))
    _runtime.set_default(hook_rt)

    calls = args.calls
    POINTS = checkpoints_for(calls)
    results: list[Result] = []

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
    # How many wrappers were *actually* retained: with a short run the
    # `i % 997` cadence hits fewer than SURVIVORS times, and asserting the
    # constant would report a leak that is really just a small sample.
    parse_survivors = len(keep)
    keep.clear()
    gc.collect()
    hook_rt.flush()

    # S4: the object model. A `Position` is built by the guest, then read
    # field by field: four frames per iteration (construct, two reads, release).
    # The read is asserted, not just performed — a getter that returned the
    # wrong field would still be fast, and speed is not the claim here.
    def construct_and_read(i: int) -> None:
        pos = mjson.Position(i % 97, i % 89)
        if pos.line != i % 97 or pos.column != i % 89:
            raise AssertionError(f"field mismatch at {i}")
        pos.close()

    results.append(measure("ctor+field", calls, construct_and_read))

    positions: list[object] = []

    def construct_and_drop(i: int) -> None:
        # Same object, released by the collector instead of by `close()`.
        pos = mjson.Position(i % 97, i % 89)
        if pos.line != i % 97:
            raise AssertionError(f"field mismatch at {i}")
        if i % 997 == 0:
            positions.append(pos)
            if len(positions) > SURVIVORS:
                positions.pop(0)

    results.append(measure("ctor/gc", calls, construct_and_drop))
    ctor_survivors = len(positions)
    positions.clear()
    gc.collect()
    hook_rt.flush()

    # A mutable field is the one shape that writes back into the guest object,
    # so it gets its own case: read, write, read back.
    def write_field(i: int) -> None:
        scan = mlex.StringScanner(TEXT, 0)
        if scan.cursor != 0:
            raise AssertionError(f"fresh scanner at {scan.cursor}")
        scan.cursor = i % 11
        if scan.cursor != i % 11:
            raise AssertionError(f"cursor did not take: {scan.cursor}")
        scan.close()

    results.append(measure("setter", calls, write_field))
    gc.collect()
    hook_rt.flush()

    report(results)

    failures = 0

    def check(label: str, ok: bool, detail: str) -> None:
        nonlocal failures
        print(f"{'ok  ' if ok else 'FAIL'} {label}: {detail}")
        if not ok:
            failures += 1

    held = {"parse/gc": parse_survivors, "ctor/gc": ctor_survivors}
    for r in results:
        expected = held.get(r.name, 0)
        check(
            f"{r.name} released everything",
            r.live_end == expected,
            f"live={r.live_end}"
            + (f" ({expected} held on purpose)" if expected else ""),
        )

    # A release the guest could not route is worse than one still pending: it
    # looks like success on this side and leaks on the other. `dropped` is the
    # only number that distinguishes the two, so it is asserted separately.
    check(
        "every release reached a table",
        hook_rt.dropped == 0,
        f"dropped={hook_rt.dropped} of {hook_rt.releases} released",
    )

    final_live = hook.live_handles()
    check("guest is empty at the end", final_live == 0, f"live={final_live}")

    # Wasm memory only grows, so a leak shows up as a curve that keeps
    # climbing. A steady one is the whole claim.
    for r in results:
        if len(r.curve) < 2:
            print(f"skip {r.name} memory plateaus: only one sample in {r.calls} calls")
            continue
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
    floor = next(r for r in results if r.name == "valid")
    print(f"frames per second (valid): {calls / floor.seconds:,.0f}")

    hook.close()
    hook_rt.close()

    if failures:
        print(f"\n{failures} check(s) failed")
        return 1
    print("\nno leaks: every handle the guest made was released")
    return 0


if __name__ == "__main__":
    sys.exit(main())
