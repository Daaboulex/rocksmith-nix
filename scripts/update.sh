#!/usr/bin/env bash
# update.sh — Generic update script for Nix Packaging Standard v1.1
# This repo has upstream type "none" (own fork), so this script is a no-op.
# It exists to satisfy the standard file structure requirement.
#
# Exit codes: 0 = no update needed, 1 = update failed, 2 = network error

set -euo pipefail

output() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/null}"; }

output "updated" "false"
output "package_name" "rocksmith"

echo "No upstream tracking configured (type: none). Nothing to update."
exit 0
