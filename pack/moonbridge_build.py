"""A PEP 517 build backend that packs generated bindings into a wheel.

This file is the whole build system. There is no `setuptools`, no `flit`, no
build dependency to download: a bridge package is a directory of generated
`.py`/`.pyi` files plus one wasm binary, and a wheel is a zip with the right
metadata. Anything more would be a dependency a user has to install before
they can install us, for no benefit.

Used by `scripts/wheel.sh`, which stages a project directory containing this
file, `pyproject.toml`, the generated package and the wasm binary, then asks
pip for a wheel.

Deliberately *not* here: compiling the wasm. That is `moon build`'s job, and a
build backend that shells out to a compiler is a build backend that only works
on the machine it was written on.
"""

from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import re
import tarfile
import zipfile
from pathlib import Path
from typing import Any, Iterator

#: Where the project description lives, relative to the project directory.
CONFIG_NAME = "moonbridge_wheel.json"

#: Fixed timestamp for every archive member, so two builds of the same inputs
#: produce byte-identical files. Overridable, as PEP 610 and reproducible-builds
#: convention both expect.
DEFAULT_EPOCH = 315532800  # 1980-01-01, the earliest a zip can express


def _config(project: Path) -> dict[str, Any]:
    with open(project / CONFIG_NAME, encoding="utf-8") as handle:
        config: dict[str, Any] = json.load(handle)
    for key in ("name", "version", "package"):
        if key not in config:
            raise RuntimeError(f"{CONFIG_NAME} is missing '{key}'")
    return config


def _normalized(name: str) -> str:
    """The wheel's spelling of a distribution name (PEP 503)."""
    return re.sub(r"[-_.]+", "_", name).lower()


def _metadata(config: dict[str, Any]) -> str:
    lines = [
        "Metadata-Version: 2.1",
        f"Name: {config['name']}",
        f"Version: {config['version']}",
        f"Summary: {config.get('summary', config['name'])}",
        "Requires-Python: >=3.9",
    ]
    for extra in config.get("requires", []):
        lines.append(f"Requires-Dist: {extra}")
    description = config.get("description")
    if description:
        lines.append("Description-Content-Type: text/markdown")
        lines.append("")
        lines.append(description)
    return "\n".join(lines) + "\n"


def _wheel_metadata() -> str:
    return (
        "Wheel-Version: 1.0\n"
        "Generator: moonbridge.build_backend\n"
        "Root-Is-Purelib: true\n"
        "Tag: py3-none-any\n"
    )


def _digest(data: bytes) -> str:
    hashed = hashlib.sha256(data).digest()
    return "sha256=" + base64.urlsafe_b64encode(hashed).rstrip(b"=").decode("ascii")


def _package_files(project: Path, package: str) -> Iterator[tuple[str, bytes]]:
    """Every file that belongs in the wheel, as `(arcname, content)`."""
    root = project / package
    if not root.is_dir():
        raise RuntimeError(f"package directory '{package}' is missing")
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if "__pycache__" in path.parts:
            continue
        yield f"{package}/{path.relative_to(root).as_posix()}", path.read_bytes()


def _add(archive: zipfile.ZipFile, arcname: str, data: bytes, epoch: int) -> None:
    info = zipfile.ZipInfo(arcname, date_time=_stamp(epoch))
    info.external_attr = 0o644 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, data)


def _stamp(epoch: int) -> tuple[int, int, int, int, int, int]:
    import time

    parts = time.gmtime(max(epoch, DEFAULT_EPOCH))
    return (parts.tm_year, parts.tm_mon, parts.tm_mday, 0, 0, 0)


def _epoch() -> int:
    raw = os.environ.get("SOURCE_DATE_EPOCH")
    return int(raw) if raw else DEFAULT_EPOCH


def build_wheel(
    wheel_directory: str,
    config_settings: dict[str, Any] | None = None,
    metadata_directory: str | None = None,
) -> str:
    """Builds the wheel and returns its file name."""
    del config_settings, metadata_directory
    project = Path.cwd()
    config = _config(project)
    epoch = _epoch()
    # The two names differ: the archive is `<name>-<version>-py3-none-any.whl`
    # while the metadata directory inside it is `<name>-<version>.dist-info`.
    stem = f"{_normalized(config['name'])}-{config['version']}"
    dist_info = f"{stem}.dist-info"
    filename = f"{stem}-py3-none-any.whl"

    entries: list[tuple[str, bytes]] = list(
        _package_files(project, config["package"])
    )
    entries.append((f"{dist_info}/METADATA", _metadata(config).encode("utf-8")))
    entries.append((f"{dist_info}/WHEEL", _wheel_metadata().encode("utf-8")))
    # `top_level.txt` is not required, but tools read it to answer "where did
    # this package install itself", and it is one line.
    entries.append(
        (f"{dist_info}/top_level.txt", (config["package"] + "\n").encode("utf-8"))
    )

    record: list[str] = []
    for arcname, data in entries:
        record.append(f"{arcname},{_digest(data)},{len(data)}")
    record.append(f"{dist_info}/RECORD,,")
    entries.append((f"{dist_info}/RECORD", ("\n".join(record) + "\n").encode("utf-8")))

    target = Path(wheel_directory)
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target / filename, "w") as archive:
        for arcname, data in entries:
            _add(archive, arcname, data, epoch)
    return filename


def build_sdist(
    sdist_directory: str, config_settings: dict[str, Any] | None = None
) -> str:
    """Builds a source archive, so `pip download` has something to fetch."""
    del config_settings
    project = Path.cwd()
    config = _config(project)
    base = f"{_normalized(config['name'])}-{config['version']}"
    filename = f"{base}.tar.gz"
    target = Path(sdist_directory)
    target.mkdir(parents=True, exist_ok=True)
    epoch = _epoch()

    members: list[tuple[str, bytes]] = [
        ("pyproject.toml", (project / "pyproject.toml").read_bytes()),
        ("moonbridge_build.py", Path(__file__).read_bytes()),
        (CONFIG_NAME, (project / CONFIG_NAME).read_bytes()),
        ("PKG-INFO", _metadata(config).encode("utf-8")),
    ]
    members.extend(
        (f"{config['package']}/{name.split('/', 1)[1]}", data)
        for name, data in _package_files(project, config["package"])
    )

    with tarfile.open(target / filename, "w:gz") as archive:
        for name, data in members:
            info = tarfile.TarInfo(f"{base}/{name}")
            info.size = len(data)
            info.mtime = epoch
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    return filename


def prepare_metadata_for_build_wheel(
    metadata_directory: str, config_settings: dict[str, Any] | None = None
) -> str:
    """Writes `.dist-info` without building the wheel, for pip's resolve step."""
    del config_settings
    config = _config(Path.cwd())
    dist_info = f"{_normalized(config['name'])}-{config['version']}.dist-info"
    target = Path(metadata_directory) / dist_info
    target.mkdir(parents=True, exist_ok=True)
    (target / "METADATA").write_text(_metadata(config), encoding="utf-8")
    (target / "WHEEL").write_text(_wheel_metadata(), encoding="utf-8")
    return dist_info


def get_requires_for_build_wheel(
    config_settings: dict[str, Any] | None = None,
) -> list[str]:
    """No build requirements: this backend imports only the standard library."""
    del config_settings
    return []


def get_requires_for_build_sdist(
    config_settings: dict[str, Any] | None = None,
) -> list[str]:
    del config_settings
    return []
