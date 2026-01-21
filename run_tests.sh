#!/usr/bin/env bash
# Run all tests for Chief Wiggum
# Usage: ./run_tests.sh [test_file...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/tests/test-runner.sh" "$@"
