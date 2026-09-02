# llvm-bootstrap

Release-builder repository for prebuilt LLVM installs.

## What this repository builds

Host platforms:

- Windows x64
- Linux x64
- macOS arm64

Enabled LLVM backends inside every host build:

- `X86`
- `AArch64`
- `WebAssembly`

## Pinned LLVM version

The LLVM ref is stored in [`llvm.version`](./llvm.version).

Current default:

```text
llvmorg-21.1.2
```

The workflow derives the release tag from that value:

- `llvmorg-21.1.2` -> GitHub release tag `llvm-21.1.2`
- a raw commit SHA -> GitHub release tag `llvm-<sha>`

## Build configuration

The builder is intentionally minimal and release-oriented:

- `-DCMAKE_BUILD_TYPE=Release`
- `-DLLVM_ENABLE_ASSERTIONS=OFF`
- `-DLLVM_ABI_BREAKING_CHECKS=FORCE_OFF`
- `-DLLVM_INCLUDE_TESTS=OFF`
- `-DLLVM_INCLUDE_BENCHMARKS=OFF`
- `-DLLVM_INCLUDE_EXAMPLES=OFF`
- `-DLLVM_INCLUDE_DOCS=OFF`
- `-DLLVM_TARGETS_TO_BUILD=X86;AArch64;WebAssembly`
- `-DBUILD_SHARED_LIBS=OFF`
- `-DLLVM_BUILD_LLVM_DYLIB=OFF`
- `-DLLVM_BUILD_LLVM_C_DYLIB=OFF`
- `-DLLVM_LINK_LLVM_DYLIB=OFF`
- `-DLLVM_ENABLE_ZLIB=OFF`
- `-DLLVM_ENABLE_ZSTD=OFF`
- `-DLLVM_ENABLE_LIBXML2=OFF`
- `-DLLVM_ENABLE_TERMINFO=OFF`
- macOS default deployment target: `11.0`
- Windows default CRT mode: `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded` (`/MT`)

The optional external dependencies are disabled so the packaged binaries are less tied to whatever happens to be installed on the GitHub runner image.

The current defaults are chosen to produce a better general-purpose package for downstream consumers:

- Windows defaults to a static LLVM build with static MSVC runtime (`/MT`)
- Linux and macOS default to static LLVM builds
- every archive carries a build manifest so consumers can see exactly which toolchain produced it

## Release assets

Each release publishes:

- `llvm-<version>-windows-x64-static.zip`
- `llvm-<version>-linux-x64-static.tar.xz`
- `llvm-<version>-macos-arm64-static.tar.xz`
- `SHA256SUMS.txt`

Each archive contains a standard LLVM install root:

- `bin/`
- `include/`
- `lib/`
- `share/`

The install is meant to stay compatible with `LLVM_SYS_211_PREFIX`.

Each archive also contains:

- `share/llvm-bootstrap/BUILDINFO.json`
- `share/licenses/llvm/LICENSE.TXT`
- `share/licenses/llvm/BLAKE3-LICENSE.txt`
- `share/licenses/llvm/XXHASH-LICENSE.txt`
- `share/licenses/llvm/MD5-LICENSE.txt`
- `share/licenses/llvm/REGEX-LICENSE.txt`
- `share/licenses/llvm/UNICODE-LICENSE.txt`
- `share/licenses/llvm/MSVCSETUPAPI-LICENSE.txt`

The license files contain the complete upstream LLVM license for the pinned ref and the separate
notices for third-party code compiled into LLVM Support. The manifest records the package
linkage/runtime mode and the build provenance used to produce it, including:

- LLVM ref and package version
- CMake and Ninja versions
- compiler/linker version details
- Windows toolset and SDK details when applicable
- macOS deployment target when applicable

The Windows archive is a better default package than the previous floating-runtime variant, but it is still not a guarantee of universal MSVC compatibility for all downstream static-link scenarios.

## GitHub Actions flow

The main workflow lives at [`.github/workflows/build.yml`](./.github/workflows/build.yml).

You can run it in two modes:

1. `workflow_dispatch` with `publish_release=true`
2. Push a Git tag like `llvm-21.1.2`

The workflow:

1. Reads the pinned ref from [`llvm.version`](./llvm.version)
2. Checks out `llvm/llvm-project` at that ref
3. Builds and installs LLVM on each supported host runner
4. Packages each install into its platform archive format
5. Uploads intermediate workflow artifacts
6. Generates `SHA256SUMS.txt`
7. Publishes or updates the matching GitHub release

The CI defaults are configured through workflow env vars:

- `LLVM_LINKAGE=Static`
- `LLVM_WINDOWS_MSVC_RUNTIME=MT`
- `LLVM_MACOS_DEPLOYMENT_TARGET=11.0`

## Triggering builds

## Local builds

`build_local.ps1` and `build_local.sh` are now the reusable source-bootstrap entrypoints for this repo.
They:

- clone `llvm-project` at the requested ref
- build and install LLVM to the requested directories
- optionally package the install

Examples:

Windows:

```powershell
./build_local.ps1
./build_local.ps1 -InstallDir C:\tmp\llvm-install
./build_local.ps1 -Package
```

Unix:

```bash
./build_local.sh
./build_local.sh --install-dir /tmp/llvm-install
./build_local.sh --package
```

### Manual trigger from GitHub Actions

Use this when you want to test or publish the current pinned LLVM version without pushing a release tag:

1. Push the repository to GitHub
2. Open the `Actions` tab
3. Select `Build LLVM Releases`
4. Click `Run workflow`
5. Leave `publish_release=true` to publish the archives to a GitHub release, or set it to `false` to only run the builds

### Tag-driven release trigger

Use this when you want the build to be tied to a specific versioned release:

1. Update [`llvm.version`](./llvm.version)
2. Commit and push that change
3. Push a matching git tag named `llvm-<version>`

Examples:

- `llvm.version = llvmorg-21.1.2` -> push tag `llvm-21.1.2`
- `llvm.version = 0123abcd` -> push tag `llvm-0123abcd`

The workflow validates that the pushed tag matches the version derived from [`llvm.version`](./llvm.version). If they do not match, the release job fails on purpose.

Example commands:

```bash
git add llvm.version
git commit -m "Bump LLVM to 21.1.2"
git push origin main
git tag llvm-21.1.2
git push origin llvm-21.1.2
```

## License

The bootstrap scripts are MIT-licensed; see [`LICENSE`](./LICENSE). Packaged LLVM installs retain
LLVM's license and the applicable LLVM Support third-party notices under `share/licenses/llvm/`.
