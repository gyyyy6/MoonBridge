//! The Python support module every generated stub imports.
//!
//! Stubs are typed against this file, so it is part of the generated contract,
//! not an implementation detail of the loader. Keeping it a string template
//! (rather than a checked-in `.py`) means the wheel and the stubs can never
//! drift apart: both are written by the same run.
//!
//! The text is type-checked by `mypy --strict` in CI together with the stubs.

///|
/// File name of the runtime module inside the generated package.
pub fn runtime_filename() -> String {
  "_runtime.py"
}

///|
/// Renders the runtime support module.
pub fn render_runtime() -> String {
  "from __future__ import annotations\n" +
  "\n" +
  "from typing import Callable\n" +
  "\n" +
  "\n" +
  "class MoonError(BaseException):\n" +
  "    \"\"\"Base class of every error raised across the MoonBridge boundary.\n" +
  "\n" +
  "    MoonBit `suberror` declarations are generated as subclasses of this type, so\n" +
  "    `except MoonError` catches any failure that originated in MoonBit.\n" +
  "    \"\"\"\n" +
  "\n" +
  "    message: str\n" +
  "\n" +
  "    def __init__(self, message: str) -> None:\n" +
  "        super().__init__(message)\n" +
  "        self.message = message\n" +
  "\n" +
  "\n" +
  "class MoonObject:\n" +
  "    \"\"\"Base class of every generated handle type.\n" +
  "\n" +
  "    A MoonBit value is never copied into Python. The Python object holds an\n" +
  "    opaque integer handle and the value keeps living in the MoonBit heap, which\n" +
  "    is what keeps identity, mutability and recursive structures intact.\n" +
  "    \"\"\"\n" +
  "\n" +
  "    _handle: int\n" +
  "\n" +
  "    def __init__(self, handle: int = 0) -> None:\n" +
  "        self._handle = handle\n" +
  "\n" +
  "    def __repr__(self) -> str:\n" +
  "        return f\"<{type(self).__name__} handle={self._handle}>\"\n" +
  "\n" +
  "\n" +
  "class Runtime:\n" +
  "    \"\"\"Dispatches encoded calls into a loaded MoonBit module.\n" +
  "\n" +
  "    The host supplies `call`, which takes a symbol name and a UTF-8 payload and\n" +
  "    returns the response payload. Keeping the transport behind one callable is\n" +
  "    what lets the same generated bindings run on wasmtime, a native shared\n" +
  "    library, or a test double.\n" +
  "    \"\"\"\n" +
  "\n" +
  "    def __init__(self, call: Callable[[str, bytes], bytes]) -> None:\n" +
  "        self._call = call\n" +
  "\n" +
  "    def invoke(self, symbol: str, payload: bytes) -> bytes:\n" +
  "        return self._call(symbol, payload)\n"
}

///|
/// Package marker that makes the generated directory a typed distribution.
pub fn render_init() -> String {
  "\"\"\"Generated Python bindings for MoonBit packages.\n" +
  "\n" +
  "This package is written by MoonBridge. Do not edit by hand.\n" +
  "\"\"\"\n" +
  "\n" +
  "from ._runtime import MoonError, MoonObject, Runtime\n" +
  "\n" +
  "__all__ = [\"MoonError\", \"MoonObject\", \"Runtime\"]\n"
}
