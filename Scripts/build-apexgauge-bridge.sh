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

# Signing identity decides whether macOS remembers "Allow".
#
# Reading CodexBar's group container (fable source = codexbar) triggers the
# "would like to access data from other apps" prompt. TCC records that consent
# against the binary's designated requirement, so an ad-hoc signature — which
# has no stable identity — loses consent on every rebuild and re-prompts
# forever. A Developer ID or Apple Development identity keeps it.
#
# Override with APEXGAUGE_SIGN_IDENTITY; set it to "-" to force ad-hoc.
if [[ -n "${APEXGAUGE_SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="${APEXGAUGE_SIGN_IDENTITY}"
else
    # `|| true` on each: grep exits non-zero when the identity class is absent,
    # and under `set -euo pipefail` that aborts the whole build.
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)
    if [[ -z "${SIGN_IDENTITY}" ]]; then
        SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Apple Development:[^"]*"' | head -1 | tr -d '"' || true)
    fi
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "Signing ad-hoc — macOS will re-prompt for cross-app access after every rebuild." >&2
    codesign --force --sign - "${OUTPUT}"
else
    echo "Signing with: ${SIGN_IDENTITY}"
    codesign --force --timestamp --options runtime --sign "${SIGN_IDENTITY}" "${OUTPUT}"
fi

echo "Built universal binary: ${OUTPUT}"
shasum -a 256 "${OUTPUT}"
echo
echo "Next: ${OUTPUT} install"
