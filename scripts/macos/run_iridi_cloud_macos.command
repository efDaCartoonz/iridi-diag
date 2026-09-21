#!/bin/sh

# Double-click / CLI launcher for iRidi Cloud Diagnostics on macOS.
# Detects environment, provides interactive menu or passes arguments to the diagnostic engine.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null || pwd)"
ENGINE="$SCRIPT_DIR/check_iridi_cloud_macos.sh"

if [ ! -f "$ENGINE" ]; then
  printf '\033[31m[ERROR] Required diagnostic engine was not found: %s\033[0m\n' "$ENGINE"
  printf 'Make sure all files from the repository or archive are present.\n'
  exit 2
fi

# Make sure executable permissions are set
chmod +x "$ENGINE" 2>/dev/null || true

# If arguments passed, pass them directly to the engine
if [ $# -gt 0 ]; then
  exec sh "$ENGINE" "$@"
fi

# Run interactive engine
sh "$ENGINE"
EXIT_CODE=$?

printf '\nLog files are stored in:\n%s/logs\n' "$SCRIPT_DIR"
exit "$EXIT_CODE"
