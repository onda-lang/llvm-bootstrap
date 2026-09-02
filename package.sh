#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 || $# -gt 7 ]]; then
  echo "usage: ./package.sh <version> <platform> <arch> <install-dir> <output-dir> [linkage] [llvm-ref]" >&2
  exit 1
fi

version="$1"
platform="$2"
arch="$3"
install_dir="$4"
output_dir="$5"
linkage="${6:-Static}"
llvm_ref="${7:-}"

linkage_token="$(printf '%s' "$linkage" | tr '[:upper:]' '[:lower:]')"
archive="$output_dir/llvm-$version-$platform-$arch-$linkage_token.tar.xz"
manifest_dir="$install_dir/share/llvm-bootstrap"
manifest_path="$manifest_dir/BUILDINFO.json"
llvm_license="$install_dir/share/licenses/llvm/LICENSE.TXT"
blake3_license="$install_dir/share/licenses/llvm/BLAKE3-LICENSE.txt"
xxhash_license="$install_dir/share/licenses/llvm/XXHASH-LICENSE.txt"
md5_license="$install_dir/share/licenses/llvm/MD5-LICENSE.txt"
regex_license="$install_dir/share/licenses/llvm/REGEX-LICENSE.txt"
unicode_license="$install_dir/share/licenses/llvm/UNICODE-LICENSE.txt"
msvc_setup_api_license="$install_dir/share/licenses/llvm/MSVCSETUPAPI-LICENSE.txt"

if [[ ! -f "$llvm_license" ]] \
  || ! grep -Fq "Apache License v2.0 with LLVM Exceptions" "$llvm_license" \
  || ! grep -Fq "END OF TERMS AND CONDITIONS" "$llvm_license"; then
  echo "complete LLVM license not found at $llvm_license" >&2
  exit 1
fi

if [[ ! -f "$blake3_license" || ! -f "$xxhash_license" || ! -f "$md5_license" \
  || ! -f "$regex_license" || ! -f "$unicode_license" || ! -f "$msvc_setup_api_license" ]] \
  || ! grep -Fq "CC0 1.0 Universal" "$blake3_license" \
  || ! grep -Fq "Copyright (C) 2012-2023, Yann Collet" "$xxhash_license" \
  || ! grep -Fq "Redistributions in binary form must reproduce" "$xxhash_license" \
  || ! grep -Fq "Alexander Peslyak" "$md5_license" \
  || ! grep -Fq "Henry Spencer" "$regex_license" \
  || ! grep -Fq "Todd C. Miller" "$regex_license" \
  || ! grep -Fq "1991-2015 Unicode" "$unicode_license" \
  || ! grep -Fq "1991-2022 Unicode" "$unicode_license" \
  || ! grep -Fq "Copyright (C) Microsoft Corporation" "$msvc_setup_api_license"; then
  echo "complete LLVM third-party license material not found under $install_dir/share/licenses/llvm" >&2
  exit 1
fi

mkdir -p "$output_dir" "$manifest_dir"

cmake_version="$(cmake --version | head -n 1)"
ninja_version="$(ninja --version | head -n 1)"
llvm_config_version="$("$install_dir/bin/llvm-config" --version)"
compiler_path="$(command -v clang || command -v gcc || command -v cc || true)"
compiler_version=""
if [[ -n "$compiler_path" ]]; then
  compiler_version="$("$compiler_path" --version | head -n 1)"
fi

runner_image=""
if [[ -n "${ImageOS:-}" || -n "${ImageVersion:-}" ]]; then
  runner_image="${ImageOS:-} ${ImageVersion:-}"
  runner_image="${runner_image#"${runner_image%%[![:space:]]*}"}"
  runner_image="${runner_image%"${runner_image##*[![:space:]]}"}"
fi

macos_deployment_target=""
if [[ "$platform" == "macos" ]]; then
  macos_deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
fi

export PKG_LLVM_VERSION="$version"
export PKG_LLVM_REF="$llvm_ref"
export PKG_PLATFORM="$platform"
export PKG_ARCH="$arch"
export PKG_LINKAGE="$linkage"
export PKG_ARCHIVE_NAME="$(basename "$archive")"
export PKG_CMAKE_VERSION="$cmake_version"
export PKG_NINJA_VERSION="$ninja_version"
export PKG_LLVM_CONFIG_VERSION="$llvm_config_version"
export PKG_COMPILER_PATH="$compiler_path"
export PKG_COMPILER_VERSION="$compiler_version"
export PKG_RUNNER_IMAGE="$runner_image"
export PKG_MACOS_DEPLOYMENT_TARGET="$macos_deployment_target"

python3 - "$manifest_path" <<'PY'
import json
import os
import platform
import sys

path = sys.argv[1]
data = {
    "package_version": 1,
    "llvm_version": os.environ["PKG_LLVM_VERSION"],
    "llvm_ref": os.environ.get("PKG_LLVM_REF", ""),
    "platform": os.environ["PKG_PLATFORM"],
    "architecture": os.environ["PKG_ARCH"],
    "linkage": os.environ["PKG_LINKAGE"],
    "runtime": "",
    "archive_name": os.environ["PKG_ARCHIVE_NAME"],
    "generator": "Ninja",
    "cmake_version": os.environ["PKG_CMAKE_VERSION"],
    "ninja_version": os.environ["PKG_NINJA_VERSION"],
    "llvm_config_version": os.environ["PKG_LLVM_CONFIG_VERSION"],
    "runner_os": platform.platform(),
    "host_architecture": platform.machine(),
    "compiler_path": os.environ.get("PKG_COMPILER_PATH", ""),
    "compiler_version": os.environ.get("PKG_COMPILER_VERSION", ""),
    "runner_image": os.environ.get("PKG_RUNNER_IMAGE", ""),
    "macos_deployment_target": os.environ.get("PKG_MACOS_DEPLOYMENT_TARGET", ""),
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=False)
    f.write("\n")
PY

rm -f "$archive"
tar -cJf "$archive" -C "$install_dir" .

if [[ ! -f "$archive" ]]; then
  echo "failed to produce archive at $archive" >&2
  exit 1
fi

printf '%s\n' "$archive"
