#!/usr/bin/env bash
# Native tests for the rules, then a wasm type check of both packages.
set -euo pipefail
cd "$(dirname "$0")/.."
odin test game -define:ODIN_TEST_THREADS=1 -o:speed
odin check src/web -collection:psp=. -target:js_wasm32 -vet-shadowing -vet-unused
