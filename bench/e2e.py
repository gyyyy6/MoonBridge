"""End-to-end: generated Python calls the real MoonBit guest through wasmtime.

Nothing here is hand-written per function. `parse`, `valid`, `Json.stringify`,
`Position`, `StringScanner` and `ParseError` all come from one generator run
over published `moonbitlang/core` interfaces, and the bodies are the ones
`--bind` emitted.

The last section is the S4 claim: a generated class can be *used*. It is
constructed by the guest, its fields are read through generated getters, a
mutable field is written and read back, and it is passed as a handle argument
to another guest function.

Run it with `scripts/e2e.sh`, or by hand:

    python bench/e2e.py --package _gen \
        --wasm _build/wasm/release/build/guest_gen/guest_gen.wasm
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="_gen", help="directory holding the generated package")
    parser.add_argument("--wasm", required=True)
    args = parser.parse_args()

    sys.path.insert(0, str(Path(args.package).resolve()))
    from moonbridge import _runtime, _wasmtime  # noqa: PLC0415
    from moonbridge import moonbitlang__core__builtin as mbuiltin  # noqa: PLC0415
    from moonbridge import moonbitlang__core__json as mjson  # noqa: PLC0415
    from moonbridge import moonbitlang__core__lexbuf as mlex  # noqa: PLC0415

    host, rt = _wasmtime.open_runtime(Path(args.wasm))
    # The generated functions reach the runtime through the module-level
    # default, which is what a binding installed as a library relies on.
    _runtime.set_default(rt)

    failures = 0

    def check(label: str, got: object, want: object) -> None:
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")
        else:
            print(f"ok   {label}: {got!r}")

    check("valid(ok)", mjson.valid('{"a": [1, 2, 3]}'), True)
    check("valid(bad)", mjson.valid("{oops"), False)

    # S4: the object model, end to end. `Position` is a `pub(all) struct` in
    # `moonbitlang/core/json`; its constructor, getters and the table tag all
    # come out of the plan, so none of this is typed by hand.
    print()
    print("-- constructed objects --")
    pos = mjson.Position(3, 7)
    check("Position is a generated class", type(pos).__name__, "Position")
    check("Position has a table tag", type(pos).moon_type_id > 0, True)
    check("field line", pos.line, 3)
    check("field column", pos.column, 7)
    check("live after construct", host.live_handles(), 1)
    pos.close()
    check("live after close", host.live_handles(), 0)
    check("handle id after close", pos.handle_id, 0)

    # A handle argument: two objects, compared by the guest, not by Python.
    left, right = mjson.Position(1, 2), mjson.Position(1, 2)
    check("equal(same)", left.equal(right), True)
    check("equal(different)", left.equal(mjson.Position(9, 9)), False)
    for obj in (left, right):
        obj.close()
    check("live after handle arguments", host.live_handles(), 0)

    # A mutable field: written through the generated setter, then read back
    # through the generated getter. Nothing about this pair is in the runtime.
    scan = mlex.StringScanner("hello world", 0)
    check("mut field read", scan.cursor, 0)
    scan.cursor = 6
    check("mut field written", scan.cursor, 6)
    check("read-only field still reads", scan.data, "hello world")
    scan.close()
    check("live after scanner", host.live_handles(), 0)

    print()
    print("-- handles through functions --")
    doc = mjson.parse('{"b": "x", "a": [1, 2, 3]}')
    print("ok   parse ->", doc, "handle", doc.handle_id)
    check("parse returns a Json", isinstance(doc, mbuiltin.Json), True)
    check("round trip", doc.stringify(), '{"b":"x","a":[1,2,3]}')
    check("live after parse", host.live_handles(), 1)

    # A context manager releases the guest object without waiting for the
    # garbage collector, which is what makes the leak test deterministic.
    with mjson.parse("[1, 2]") as inner:
        check("nested live", host.live_handles(), 2)
        check("nested stringify", inner.stringify(), "[1,2]")
    check("live after with", host.live_handles(), 1)

    doc.close()
    check("live after close", host.live_handles(), 0)
    check("handle id after close", doc.handle_id, 0)
    doc.close()
    check("close is idempotent", host.live_handles(), 0)

    try:
        mjson.parse("{oops")
    except _runtime.MoonError as exc:
        # The guest's own message crosses the boundary unchanged.
        print("ok   parse error:", exc)
    else:
        failures += 1
        print("FAIL parse error was not raised")

    # The stub says `stringify` returns `str` and that a document is a `Json`.
    # If either were a wish rather than the truth, this is where it shows.
    check("closed doc is empty", doc.handle_id, 0)

    # A release that the guest could not route to a table would look like
    # success from here and leak over there. This is the number that says it
    # did not happen.
    check("every release reached a table", rt.dropped, 0)
    print(f"ok   {rt.calls} frames, {rt.releases} handles released")

    rt.close()
    host.close()

    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print("\nall end-to-end checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
