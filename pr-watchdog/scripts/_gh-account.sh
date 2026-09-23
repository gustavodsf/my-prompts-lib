# Sourced by scan.sh and prep.sh. Pins gh to one account for the calling process.
#
# The gh "active account" lives in ~/.config/gh/hosts.yml -- global state shared by every
# process on the machine. Any other shell running `gh auth switch` (another Claude session on
# a personal repo, say) flips it mid-run, and gh calls here then answer as the wrong identity:
# a 404 on the private repo, or an error string written where the bundle expects data.
# Exporting GH_TOKEN takes precedence over the stored active account, so this process is
# immune to a concurrent flip and, unlike `gh auth switch`, inflicts none on anybody else.
#
# From Brendan Glancy's build. Kept verbatim in intent; the default is generalised so the
# skill ships without one person's login baked in -- it resolves whoever is active at startup
# and pins that, which is still immune to a mid-run flip.
GH_ACCOUNT="${WATCHDOG_GH_ACCOUNT:-}"
if [ -z "$GH_ACCOUNT" ]; then
  GH_ACCOUNT=$(gh auth status --active 2>/dev/null \
    | sed -n 's/.*account \([A-Za-z0-9_-]*\).*/\1/p' | head -1)
fi
if [ -z "$GH_ACCOUNT" ]; then
  echo "${0##*/}: no active gh account. Run 'gh auth login', or set WATCHDOG_GH_ACCOUNT." >&2
  exit 1
fi
GH_TOKEN=$(gh auth token --user "$GH_ACCOUNT" 2>/dev/null) || GH_TOKEN=""
if [ -z "$GH_TOKEN" ]; then
  echo "${0##*/}: no gh token for account '$GH_ACCOUNT' -- run: gh auth login --user $GH_ACCOUNT" >&2
  exit 1
fi
export GH_TOKEN
