#!/bin/bash
# stats.sh — download counts per release asset of the public repo.
# DMG ≈ new installs (and Sparkle full updates); .delta ≈ auto-updates.
set -euo pipefail
gh api repos/igorlourenco/thermal/releases \
    -q '.[] | .tag_name as $t | .assets[] | "\($t)\t\(.name)\t\(.download_count)"' \
    | column -t
