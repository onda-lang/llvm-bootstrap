"""Validate the Debian 12 ABI and execute a consumer of the packaged static SDK."""

from pathlib import Path
import os
import re
import shlex
import struct
import subprocess
import sys
import tempfile


LIMITS = {"GLIBC": (2, 36), "GLIBCXX": (3, 4, 30), "CXXABI": (1, 3, 13)}
MACHINES = {"x64": 62, "arm64": 183}


def audit_elf(root, architecture):
    maximums = {}
    count = 0
    for directory in (root / "bin", root / "lib"):
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            with path.open("rb") as stream:
                header = stream.read(20)
            if not header.startswith(b"\x7fELF"):
                continue
            if (len(header) != 20 or header[4:6] != b"\x02\x01"
                    or struct.unpack_from("<H", header, 18)[0] != MACHINES[architecture]):
                raise RuntimeError(f"{path}: expected little-endian {architecture} ELF64")
            count += 1
            versions = subprocess.check_output(
                ["readelf", "--wide", "--version-info", str(path)], text=True,
                env={**os.environ, "LC_ALL": "C"},
            )
            for family, suffix in re.findall(
                r"\bName: (GLIBCXX|GLIBC|CXXABI)_([A-Za-z0-9_.]+)",
                versions.partition("Version needs section")[2],
            ):
                # Packed relative relocations were added in glibc 2.36.
                if family == "GLIBC" and suffix == "ABI_DT_RELR":
                    version = (2, 36)
                elif re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", suffix):
                    version = tuple(map(int, suffix.split(".")))
                else:
                    raise RuntimeError(f"{path}: unsupported requirement {family}_{suffix}")
                if version > LIMITS[family]:
                    limit = ".".join(map(str, LIMITS[family]))
                    raise RuntimeError(f"{path}: requires {family}_{suffix}, exceeds {family}_{limit}")
                maximums[family] = max(maximums.get(family, ()), version)
    if count == 0:
        raise RuntimeError(f"{root}: no ELF files found")
    versions = ", ".join(
        f"{family}_{'.'.join(map(str, version))}" for family, version in sorted(maximums.items())
    )
    print(f"Checked {count} {architecture} ELF files; maximum requirements: {versions}")


def check_package(root, architecture):
    audit_elf(root, architecture)
    config = root / "bin/llvm-config"
    tests = Path(__file__).resolve().parent

    def flags(*arguments):
        return shlex.split(subprocess.check_output([str(config), *arguments], text=True))

    with tempfile.TemporaryDirectory(prefix="llvm-sdk-consumer-") as temporary:
        temporary = Path(temporary)
        (temporary / "bin").mkdir()
        consumer_object = temporary / "consumer.o"
        consumer = temporary / "bin/consumer"
        subprocess.run([
            *shlex.split(os.environ.get("CC", "cc")), *flags("--cflags"),
            "-std=c11", "-Wall", "-Wextra", "-Werror", "-c", str(tests / "jit_smoke.c"),
            "-o", str(consumer_object),
        ], check=True)
        subprocess.run([
            *shlex.split(os.environ.get("CXX", "c++")), str(consumer_object),
            *flags("--ldflags", "--link-static", "--libfiles", "core", "irreader", "orcjit", "native",
                   "--system-libs"), "-o", str(consumer),
        ], check=True)
        audit_elf(temporary, architecture)
        subprocess.run([str(consumer), str(tests / "smoke.ll")], check=True, timeout=30)
        for triple, machine in [
            ("x86_64-unknown-linux-gnu", 62),
            ("aarch64-unknown-linux-gnu", 183),
            ("wasm32-unknown-unknown", None),
        ]:
            output = temporary / f"{triple}.o"
            subprocess.run([
                str(root / "bin/llc"), "-filetype=obj", f"-mtriple={triple}",
                str(tests / "smoke.ll"), "-o", str(output),
            ], check=True, timeout=30)
            header = output.read_bytes()[:20]
            if machine is None:
                valid = header.startswith(b"\0asm")
            else:
                valid = header.startswith(b"\x7fELF") and struct.unpack_from("<H", header, 18)[0] == machine
            if not valid:
                raise RuntimeError(f"{triple}: wrong object architecture")
            print(f"Object emission passed: {triple}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in MACHINES:
        sys.exit(f"usage: {sys.argv[0]} <install-root> <x64|arm64>")
    try:
        check_package(Path(sys.argv[1]).resolve(), sys.argv[2])
    except (RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
