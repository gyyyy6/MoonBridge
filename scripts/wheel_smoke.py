"""Smoke test for the installed wheel, not for the source tree.

Run by `scripts/wheel.sh` from a directory that is not the repository, so
`import moonbridge` has to resolve to site-packages: if the wheel were missing a
file, the import would still find `_gen/` when run from the repo and the check
would prove nothing.

Everything here is user-facing API. No `_codec`, no frame building, no host
plumbing — the point is whether a person who ran `pip install` can do their work.
"""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    import moonbridge

    package = Path(moonbridge.__file__).resolve().parent
    print(f"ok   imported from: {package}")

    # The wasm binary travels inside the wheel; a caller configures nothing.
    guest_file = package / "_guest.wasm"
    if not guest_file.is_file():
        print(f"FAIL no guest wasm next to the package: {guest_file}")
        return 1
    print(f"ok   guest wasm shipped with the wheel: {guest_file.stat().st_size} bytes")

    failures = 0

    def check(label: str, got: object, want: object) -> None:
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")
        else:
            print(f"ok   {label}: {got!r}")

    host, runtime = moonbridge.install()

    from moonbridge import moonbitlang__core__json as mjson
    from moonbridge import gyyyy6__moonbridge__callbacks as mcb

    # Real work: parse, walk, re-serialise.
    check("valid", mjson.valid('{"a": [1, 2, 3]}'), True)
    with mjson.parse('{"b": "x", "a": [1, 2, 3]}') as doc:
        check("round trip", doc.stringify(), '{"b":"x","a":[1,2,3]}')

    # An object with fields, constructed by the guest.
    pos = mjson.Position(12, 34)
    check("field line", pos.line, 12)
    check("field column", pos.column, 34)
    pos.close()

    # Containers, the S5 addition, through the installed package. A container
    # copies the values it is given, so the handles used to build it are
    # released immediately after — which is also why the final count can be
    # asserted as zero rather than "small".
    parts = [mjson.Json.number(1.5), mjson.Json.string("x")]
    array = mjson.Json.array(parts)
    for part in parts:
        part.close()
    check("list -> Array", array.stringify(), '[1.5,"x"]')
    array.close()

    value = mjson.Json.boolean(True)
    obj = mjson.Json.object_({"k": value})
    value.close()
    check("dict -> Map", obj.stringify(), '{"k":true}')
    obj.close()

    # A callback, i.e. the wasm import the wheel's guest carries.
    check("callback", mcb.call_with(lambda x: x * 2, 21), 42)

    # A typed failure, i.e. the error class the module registered at import.
    try:
        mjson.parse("{oops")
    except mjson.ParseError as exc:
        print(f"ok   typed exception: {type(exc).__name__}: {exc}")
    except moonbridge.MoonError as exc:
        failures += 1
        print(f"FAIL exception was generic: {type(exc).__name__}: {exc}")
    else:
        failures += 1
        print("FAIL exception was not raised")

    check("every handle released", host.live_handles(), 0)
    runtime.close()
    host.close()

    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print("\nwheel installed and functional")
    return 0


if __name__ == "__main__":
    sys.exit(main())
