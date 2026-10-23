#!/usr/bin/env bash
# ci-signal.sh record <outDir> <pr> <sha>   -- append this review's CI signal
# ci-signal.sh report                        -- current streak and recent history
#
# Why this exists: the watchdog cannot run tests, so CI is its only evidence that code
# works. When a gate silently skips, "nothing failed" and "nothing ran" look identical in
# checks.txt. One PR reporting skipped checks reads as a footnote; six in a row is a broken
# pipeline, and nothing in a per-PR summary can see that. This file is the memory.
set -euo pipefail

WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
LOG="$WS/ci-signal.json"
# Two tiers, because not every skip is a problem.
#   GATE_RE   -- anything that produces evidence. Tracked for the streak.
#   MUST_RE   -- Build and the test matrix. If these skip, nothing proved the code works.
# Calibrated 2026-08-26: PR 3015 skipped only "Run Migrations" (conditional by design, no
# migrations in the diff) while PR 3019 skipped Build AND tests. Only the second is
# pathological, so a blanket "any skip" rule would cry wolf on every PR.
# Unanchored on purpose (Brendan Glancy): '^build$' matched the job named exactly "Build" and
# nothing else, so a matrix rename to "Build / build" or "build (api)" would skip undetected
# and blocksOnEvidence would stay false. The `test` half was never anchored, so the anchor
# bought nothing and cost a silent failure.
GATE_RE='(test|build|cdk|migration|lint|typecheck|e2e|integration)'
MUST_RE='(build|test)'

[ -f "$LOG" ] || echo '[]' > "$LOG"

case "${1:-report}" in
record)
  OUT="${2:?outDir}"; PR="${3:?pr}"; SHA="${4:?sha}"
  CHECKS="$OUT/checks.txt"
  [ -s "$CHECKS" ] || [ -s "$OUT/checks.json" ] || exit 0

  # checks.json is structured, so parse that rather than regexing the derived TSV. Falls back
  # to checks.txt for bundles built before prep.sh started emitting JSON.
  if [ -s "$OUT/checks.json" ]; then
    read -r total skipped failed passed gates gates_skipped must must_skipped <<<"$(
      jq -r --arg re "$GATE_RE" --arg mre "$MUST_RE" '
        def norm: (.state // "") | ascii_downcase;
        def nm:   (.name  // "") | ascii_downcase;
        [ .[] | {s: norm, n: nm} ] as $c
        | [ ($c | length),
            ($c | map(select(.s | test("skip"))) | length),
            ($c | map(select(.s | test("fail"))) | length),
            ($c | map(select(.s | test("pass|success"))) | length),
            ($c | map(select(.n | test($re))) | length),
            ($c | map(select((.n | test($re)) and (.s | test("skip")))) | length),
            ($c | map(select(.n | test($mre))) | length),
            ($c | map(select((.n | test($mre)) and (.s | test("skip")))) | length) ]
        | @tsv' "$OUT/checks.json" | tr '\t' ' '
    )"
    MUST_SKIPPED_NAMES=$(jq -r --arg mre "$MUST_RE" '
      [ .[] | select(((.name // "") | ascii_downcase | test($mre))
                 and ((.state // "") | ascii_downcase | test("skip"))) | .name ]
      | join("; ")' "$OUT/checks.json")
  else
    read -r total skipped failed passed gates gates_skipped must must_skipped <<<"$(
      awk -F"\t" -v re="$GATE_RE" -v mre="$MUST_RE" '
        NF>=2 {
          t++
          s=tolower($1); n=tolower($2)
          if (s ~ /skip/)  sk++
          if (s ~ /fail/)  f++
          if (s ~ /pass|success/) p++
          if (n ~ re) { g++; if (s ~ /skip/) gs++ }
          if (n ~ mre) { m++; if (s ~ /skip/) ms++ }
        }
        END { printf "%d %d %d %d %d %d %d %d", t, sk+0, f+0, p+0, g+0, gs+0, m+0, ms+0 }' "$CHECKS"
    )"
    MUST_SKIPPED_NAMES=$(awk -F"\t" -v mre="$MUST_RE" '
      NF>=2 && tolower($2) ~ mre && tolower($1) ~ /skip/ {printf "%s%s", (n++?"; ":""), $2}' "$CHECKS")
  fi

  jq --arg pr "$PR" --arg sha "${SHA:0:12}" \
     --argjson total "$total" --argjson skipped "$skipped" \
     --argjson failed "$failed" --argjson passed "$passed" \
     --argjson gates "$gates" --argjson gatesSkipped "$gates_skipped" \
     --argjson must "$must" --argjson mustSkipped "$must_skipped" \
     --arg mustSkippedNames "${MUST_SKIPPED_NAMES:-}" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
     . + [{pr:$pr, sha:$sha, at:$at, total:$total, skipped:$skipped, failed:$failed,
           passed:$passed, gates:$gates, gatesSkipped:$gatesSkipped,
           mustRun:$must, mustRunSkipped:$mustSkipped, mustRunSkippedNames:$mustSkippedNames,
           noGateSignal: ($gates > 0 and $gatesSkipped == $gates),
           blocksOnEvidence: ($mustSkipped > 0)}]
     | .[-40:]' "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  ;;
report)
  jq '
    (reverse | [foreach .[] as $r (true; . and $r.noGateSignal; .) ]
      | (index(false) // length)) as $streak
    | { reviews: length,
        streakWithNoGateSignal: $streak,
        recent: (reverse | .[0:6]
          | map({pr, sha, gates, gatesSkipped, mustRunSkipped, mustRunSkippedNames,
                 failed, noGateSignal, blocksOnEvidence})),
        verdict: (if $streak >= 3
          then "PIPELINE SUSPECT — \($streak) consecutive reviews with every build/test gate skipped. CI is proving nothing; treat a green checks list as unverified until a human confirms the gate config."
          elif $streak > 0
          then "\($streak) recent review(s) had no build/test signal. Watch it."
          else "gates are producing signal" end) }' "$LOG"
  ;;
*) echo "usage: ci-signal.sh record <outDir> <pr> <sha> | report" >&2; exit 2 ;;
esac
