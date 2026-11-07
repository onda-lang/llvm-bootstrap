from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

from check_linux_package import audit_elf

ARCHITECTURE = {"x86_64": "x64", "aarch64": "arm64"}.get(platform.machine())


@unittest.skipUnless(ARCHITECTURE and shutil.which("cc") and shutil.which("readelf"),
                     "requires a Linux x64/ARM64 C compiler and readelf")
class LinuxAbiTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="llvm-abi-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "bin").mkdir()
        (self.root / "lib").mkdir()

    def build_consumer(self, version):
        provider = self.root / "provider.c"
        provider.write_text("int fixture(void) { return 0; }\n")
        version_script = self.root / "versions.map"
        version_script.write_text(f"{version} {{ global: fixture; }};\n")
        library = self.root / "lib/libfixture.so"
        subprocess.run([
            "cc", "-shared", "-fPIC", str(provider), f"-Wl,--version-script={version_script}",
            "-o", str(library),
        ], check=True)
        source = self.root / "consumer.c"
        source.write_text("extern int fixture(void); int main(void) { return fixture(); }\n")
        subprocess.run(["cc", str(source), str(library), "-o", str(self.root / "bin/consumer")], check=True)

    def test_accepts_debian_12_symbol_versions(self):
        for version in ("GLIBC_2.9", "GLIBC_2.36", "GLIBC_ABI_DT_RELR",
                        "GLIBCXX_3.4.30", "CXXABI_1.3.13"):
            with self.subTest(version=version):
                self.build_consumer(version)
                audit_elf(self.root, ARCHITECTURE)

    def test_rejects_newer_symbol_versions(self):
        for version in ("GLIBC_2.37", "GLIBCXX_3.4.31", "CXXABI_1.3.14", "GLIBC_PRIVATE"):
            with self.subTest(version=version):
                self.build_consumer(version)
                with self.assertRaisesRegex(RuntimeError, version.replace(".", r"\.")):
                    audit_elf(self.root, ARCHITECTURE)

    def test_rejects_wrong_architecture(self):
        self.build_consumer("GLIBC_2.36")
        other = "arm64" if ARCHITECTURE == "x64" else "x64"
        with self.assertRaisesRegex(RuntimeError, f"expected little-endian {other} ELF64"):
            audit_elf(self.root, other)

    def test_rejects_empty_package(self):
        with self.assertRaisesRegex(RuntimeError, "no ELF files"):
            audit_elf(self.root, ARCHITECTURE)


if __name__ == "__main__":
    unittest.main()
