#!/usr/bin/env bash

set -euo pipefail

for tool in swiftc lipo shasum codesign; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Error: ${tool} was not found. Install Xcode Command Line Tools and try again." >&2
        exit 127
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${SCRIPT_DIR}/apexgauge-bridge.swift"
DIST_DIR="${REPO_ROOT}/dist"
OUTPUT="${DIST_DIR}/apexgauge-bridge"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apexgauge-bridge.XXXXXX")"

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

mkdir -p "${DIST_DIR}"

# The bridge runs on the Claude Code status line hot path, so it is compiled
# rather than interpreted: `swift file.swift` re-parses on every render.
echo "Building apexgauge-bridge for arm64-apple-macosx13..."
swiftc -O -whole-module-optimization \
    -target arm64-apple-macosx13 \
    "${SOURCE}" \
    -o "${BUILD_DIR}/apexgauge-bridge-arm64"

echo "Building apexgauge-bridge for x86_64-apple-macosx13..."
swiftc -O -whole-module-optimization \
    -target x86_64-apple-macosx13 \
    "${SOURCE}" \
    -o "${BUILD_DIR}/apexgauge-bridge-x86_64"

lipo -create \
    "${BUILD_DIR}/apexgauge-bridge-arm64" \
    "${BUILD_DIR}/apexgauge-bridge-x86_64" \
    -output "${OUTPUT}"
chmod +x "${OUTPUT}"
codesign --force --sign - "${OUTPUT}"

echo "Built universal binary: ${OUTPUT}"
shasum -a 256 "${OUTPUT}"
echo
echo "Next: ${OUTPUT} install"
