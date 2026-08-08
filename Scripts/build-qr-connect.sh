#!/usr/bin/env bash

set -euo pipefail

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Error: swiftc was not found. Install Xcode or the Swift toolchain and try again." >&2
    exit 127
fi

if ! command -v lipo >/dev/null 2>&1; then
    echo "Error: lipo was not found. Install Xcode Command Line Tools and try again." >&2
    exit 127
fi

if ! command -v shasum >/dev/null 2>&1; then
    echo "Error: shasum was not found." >&2
    exit 127
fi

if ! command -v codesign >/dev/null 2>&1; then
    echo "Error: codesign was not found. Install Xcode Command Line Tools and try again." >&2
    exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${SCRIPT_DIR}/qr-connect.swift"
DIST_DIR="${REPO_ROOT}/dist"
OUTPUT="${DIST_DIR}/qr-connect"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apexgauge-qr-connect.XXXXXX")"

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

mkdir -p "${DIST_DIR}"

echo "Building qr-connect for arm64-apple-macosx13..."
swiftc -O -whole-module-optimization \
    -target arm64-apple-macosx13 \
    "${SOURCE}" \
    -o "${BUILD_DIR}/qr-connect-arm64"

echo "Building qr-connect for x86_64-apple-macosx13..."
swiftc -O -whole-module-optimization \
    -target x86_64-apple-macosx13 \
    "${SOURCE}" \
    -o "${BUILD_DIR}/qr-connect-x86_64"

lipo -create \
    "${BUILD_DIR}/qr-connect-arm64" \
    "${BUILD_DIR}/qr-connect-x86_64" \
    -output "${OUTPUT}"
chmod +x "${OUTPUT}"
codesign --force --sign - "${OUTPUT}"

echo "Built universal binary: ${OUTPUT}"
shasum -a 256 "${OUTPUT}"
