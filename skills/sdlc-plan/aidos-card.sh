#!/usr/bin/env bash
# Print the 4-block AIDOS card (Problem -> Solution -> Tech Design -> Testing) from a design.md.
# AIDOS: https://github.com/shobman/aidos . Usage: aidos-card.sh <design.md>
set -euo pipefail
design="${1:?usage: aidos-card.sh <design.md>}"
[[ -f "$design" ]] || { echo "not found: $design" >&2; exit 1; }
section() { awk -v h="^## $1\\\\." '$0 ~ h {on=1; next} /^## / {on=0} on' "$design" | sed '/^[[:space:]]*$/d'; }
title="$(head -1 "$design" | sed 's/^# //; s/ — Design.*//')"
type="$(sed -nE 's/^Type: *//p' "$design" | head -1)"
printf '# AIDOS card: %s%s\n\n' "$title" "${type:+ ($type)}"
printf '## 1. Problem\n\n%s\n\n' "$(section 1 | grep -v 'acceptance test:' | grep -v '^Each AC')"
printf '## 2. Solution\n\n%s\n\n' "$(section 2)"
printf '## 3. Tech Design\n\n%s\n\n%s\n\n' "$(section 3)" "$(section 4 | grep '^|')"
printf '## 4. Testing\n\n%s\n\nOut of scope:\n%s\n' "$(section 1 | grep 'AC-')" "$(section 5)"
