# Sourced by prep.sh and prep-local.sh. Paths never handed to a reviewer.
#
# Two rules, both about not paying twice:
#   Generated output is checked by CI and regenerated from a source file that IS reviewed.
#   Reviewing it reviews the generator, not the author.
#   Lockfiles and snapshots are machine-written; a human did not choose those bytes.
#
# Measured 2026-08-28 on TECH-3823: prisma/generated was 5,652 of 9,611 diff lines -- 59% of
# the change, and every line of it derives from schema.prisma, which was in the reviewed
# remainder. Excluding it lost no coverage and removed more than half the input.
#
# git pathspec form, used as: git diff "$MB..$SHA" -- . $EXCLUDE_PATHSPEC
EXCLUDE_GLOBS=(
  'prisma/generated'
  '*.lock'
  'package-lock.json'
  'pnpm-lock.yaml'
  'yarn.lock'
  '*.snap'
  'dist'
  'build'
  'coverage'
  '*.min.js'
  '*.generated.ts'
)
EXCLUDE_PATHSPEC=()
for g in "${EXCLUDE_GLOBS[@]}"; do EXCLUDE_PATHSPEC+=(":(exclude,glob)**/$g" ":(exclude,glob)$g/**" ":(exclude,glob)$g"); done
