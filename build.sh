#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 6 ]]; then
  echo "usage: ./build.sh <llvm-ref> <source-dir> <build-dir> <install-dir> [linkage] [macos-deployment-target]" >&2
  exit 1
fi

llvm_ref="$1"
source_dir="$2"
build_dir="$3"
install_dir="$4"
linkage="${5:-Static}"
macos_deployment_target="${6:-11.0}"

targets="X86;AArch64;WebAssembly"
configure_args=(
  -S "$source_dir/llvm"
  -B "$build_dir"
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$install_dir"
  -DLLVM_ENABLE_ASSERTIONS=OFF
  -DLLVM_ABI_BREAKING_CHECKS=FORCE_OFF
  -DLLVM_ENABLE_PROJECTS=
  -DLLVM_TARGETS_TO_BUILD="$targets"
  -DLLVM_INCLUDE_TESTS=OFF
  -DLLVM_INCLUDE_BENCHMARKS=OFF
  -DLLVM_INCLUDE_EXAMPLES=OFF
  -DLLVM_INCLUDE_DOCS=OFF
  -DLLVM_ENABLE_ZLIB=OFF
  -DLLVM_ENABLE_ZSTD=OFF
  -DLLVM_ENABLE_LIBXML2=OFF
  -DLLVM_ENABLE_TERMINFO=OFF
)

case "$linkage" in
  Static|static)
    configure_args+=(
      -DBUILD_SHARED_LIBS=OFF
      -DLLVM_BUILD_LLVM_DYLIB=OFF
      -DLLVM_BUILD_LLVM_C_DYLIB=OFF
      -DLLVM_LINK_LLVM_DYLIB=OFF
    )
    expected_core_lib="$install_dir/lib/libLLVMCore.a"
    ;;
  Shared|shared)
    configure_args+=(
      -DBUILD_SHARED_LIBS=ON
      -DLLVM_BUILD_LLVM_DYLIB=ON
      -DLLVM_BUILD_LLVM_C_DYLIB=ON
      -DLLVM_LINK_LLVM_DYLIB=ON
    )
    case "$(uname -s)" in
      Darwin)
        expected_core_lib="$install_dir/lib/libLLVM.dylib"
        ;;
      *)
        expected_core_lib="$install_dir/lib/libLLVM.so"
        ;;
    esac
    ;;
  *)
    echo "unsupported linkage: $linkage" >&2
    exit 1
    ;;
esac

if [[ "$(uname -s)" == "Darwin" ]]; then
  configure_args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$macos_deployment_target")
fi

cmake "${configure_args[@]}"

cmake --build "$build_dir" --config Release --target install

llvm_license_source="$source_dir/llvm/LICENSE.TXT"
blake3_license_source="$source_dir/llvm/lib/Support/BLAKE3/LICENSE"
xxhash_source="$source_dir/llvm/lib/Support/xxhash.cpp"
md5_source="$source_dir/llvm/lib/Support/MD5.cpp"
regex_license_source="$source_dir/llvm/lib/Support/COPYRIGHT.regex"
strlcpy_source="$source_dir/llvm/lib/Support/regstrlcpy.c"
convert_utf_source="$source_dir/llvm/lib/Support/ConvertUTF.cpp"
unicode_data_source="$source_dir/llvm/lib/Support/UnicodeNameToCodepointGenerated.cpp"
msvc_setup_api_source="$source_dir/llvm/include/llvm/WindowsDriver/MSVCSetupApi.h"
llvm_license_dir="$install_dir/share/licenses/llvm"
if [[ ! -f "$llvm_license_source" || ! -f "$blake3_license_source" || ! -f "$xxhash_source" \
  || ! -f "$md5_source" || ! -f "$regex_license_source" || ! -f "$strlcpy_source" \
  || ! -f "$convert_utf_source" || ! -f "$unicode_data_source" \
  || ! -f "$msvc_setup_api_source" ]]; then
  echo "LLVM license material is missing from $source_dir/llvm" >&2
  exit 1
fi

extract_comment() {
  awk -v wanted="$2" '
    /^\/\*/ { block++ }
    block == wanted { print }
    block == wanted && /^[[:space:]]*\*\/$/ { exit }
  ' "$1"
}

mkdir -p "$llvm_license_dir"
cp "$llvm_license_source" "$llvm_license_dir/LICENSE.TXT"
cp "$blake3_license_source" "$llvm_license_dir/BLAKE3-LICENSE.txt"
extract_comment "$xxhash_source" 1 > "$llvm_license_dir/XXHASH-LICENSE.txt"
extract_comment "$md5_source" 1 > "$llvm_license_dir/MD5-LICENSE.txt"
cp "$regex_license_source" "$llvm_license_dir/REGEX-LICENSE.txt"
{
  echo
  echo "Additional llvm_strlcpy notice"
  echo "================================"
  echo
  extract_comment "$strlcpy_source" 1
} >> "$llvm_license_dir/REGEX-LICENSE.txt"
{
  echo "ConvertUTF notice"
  echo "================="
  echo
  extract_comment "$convert_utf_source" 2
  echo
  echo "Unicode data notice"
  echo "==================="
  echo
  extract_comment "$unicode_data_source" 1
} > "$llvm_license_dir/UNICODE-LICENSE.txt"
sed -n '1,/^\/\/ <\/license>$/p' "$msvc_setup_api_source" \
  > "$llvm_license_dir/MSVCSETUPAPI-LICENSE.txt"

if [[ ! -x "$install_dir/bin/llvm-config" && ! -f "$install_dir/bin/llvm-config" ]]; then
  echo "llvm-config not found at $install_dir/bin/llvm-config after build" >&2
  exit 1
fi

if [[ ! -f "$expected_core_lib" ]]; then
  echo "expected LLVM library not found at $expected_core_lib after build" >&2
  exit 1
fi

if ! grep -Fq "Apache License v2.0 with LLVM Exceptions" "$llvm_license_dir/LICENSE.TXT" \
  || ! grep -Fq "END OF TERMS AND CONDITIONS" "$llvm_license_dir/LICENSE.TXT"; then
  echo "installed LLVM license is incomplete" >&2
  exit 1
fi

if ! grep -Fq "CC0 1.0 Universal" "$llvm_license_dir/BLAKE3-LICENSE.txt" \
  || ! grep -Fq "Copyright (C) 2012-2023, Yann Collet" "$llvm_license_dir/XXHASH-LICENSE.txt" \
  || ! grep -Fq "Redistributions in binary form must reproduce" "$llvm_license_dir/XXHASH-LICENSE.txt" \
  || ! grep -Fq "Alexander Peslyak" "$llvm_license_dir/MD5-LICENSE.txt" \
  || ! grep -Fq "Henry Spencer" "$llvm_license_dir/REGEX-LICENSE.txt" \
  || ! grep -Fq "Todd C. Miller" "$llvm_license_dir/REGEX-LICENSE.txt" \
  || ! grep -Fq "1991-2015 Unicode" "$llvm_license_dir/UNICODE-LICENSE.txt" \
  || ! grep -Fq "1991-2022 Unicode" "$llvm_license_dir/UNICODE-LICENSE.txt" \
  || ! grep -Fq "Copyright (C) Microsoft Corporation" \
    "$llvm_license_dir/MSVCSETUPAPI-LICENSE.txt"; then
  echo "installed LLVM third-party license material is incomplete" >&2
  exit 1
fi
