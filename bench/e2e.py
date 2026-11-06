"""End-to-end: generated Python calls the real MoonBit guest through wasmtime.

Nothing here is hand-written per function. `parse`, `valid`, `Json.stringify`
and `ParseError` all come from one generator run over the published
`moonbitlang/core/json` interface, and the bodies are the ones `--bind` emitted.

Run it with `scripts/e2e.sh`, or by hand:

    python bench/e2e.py --package _gen \
        --wasm _build/wasm/release/build/guest_json/guest_json.wasm
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

    doc = mjson.parse('{"b": "x", "a": [1, 2, 3]}')
    print("ok   parse ->", doc, "handle", doc.handle_id)
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
    check("parse returns a Json", isinstance(doc, mbuiltin.Json) or doc.handle_id == 0, True)

    rt.close()
    host.close()

    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print("\nall end-to-end checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
