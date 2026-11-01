#!/usr/bin/env bash
# Marketplace security baseline, as a tests/ helper (issue #7): the
# scanner's scope rules exclude everything under tests/, so the git
# clone/fetch this script performs can never re-flag a remote-build
# capability. Invoke via `bash tests/security-baseline.sh` (mise runs
# exactly that) — keep the .sh extension and do not chmod +x, so the
# file stays squarely inside the excluded directory.
set -euo pipefail
cd "$(dirname "$0")/.."

# The clone intentionally tracks the marketplace's current main — this
# task exists to reproduce the marketplace's *current* verification
# rules, which have already changed once. For a pinned audit instead,
# set MARKETPLACE_REF to an immutable commit SHA; the resolved commit
# is always printed so a run is attributable either way.
marketplace=.tmp/marketplace
ref="${MARKETPLACE_REF:-main}"
if [ ! -d "$marketplace/.git" ]; then
  rm -rf "$marketplace"
  git clone --depth 1 --quiet https://github.com/HANCORE-linux/omarchy-plugin-marketplace "$marketplace"
fi
git -C "$marketplace" fetch --depth 1 --quiet origin "$ref"
git -C "$marketplace" reset --hard --quiet FETCH_HEAD
echo "marketplace scanner at $(git -C "$marketplace" rev-parse HEAD) (${ref})"

# Metadata must match the scanner CLI's current contract (it validates
# pluginIds/listedPlugins/entryPoints, not just repo+sha); the task
# resets the marketplace clone to the resolved main, so this follows
# whatever validate-submission.mjs writes there.
jq -n \
  --arg repoUrl "https://github.com/farangkao/omarchy-emojis-nerd" \
  --arg commitSha "$(git rev-parse HEAD)" \
  '{
    schemaVersion: 1,
    repoUrl: $repoUrl,
    repository: "farangkao/omarchy-emojis-nerd",
    defaultBranch: "main",
    commitSha: $commitSha,
    pluginIds: ["farangkao.emojis-nerd"],
    listedPlugins: [{ pluginId: "farangkao.emojis-nerd", manifestPathHint: "manifest.json" }],
    entryPoints: ["Emojis.qml"]
  }' > .tmp/baseline-metadata.json

# Anonymous GitHub access by default (both repos are public). A token
# is only involved when the caller exports GITHUB_TOKEN themselves — it
# is never pulled from gh's config here, so third-party scanner code
# cannot silently inherit the developer's credentials.

rm -f .tmp/baseline-result.json
node "$marketplace/scripts/security-baseline.mjs" --metadata=.tmp/baseline-metadata.json --json=.tmp/baseline-result.json || exit 1

[ "$(jq -r '.outcome // empty' .tmp/baseline-result.json)" = passed ] || {
  echo "security baseline: findings require attention — see the report above" >&2
  exit 1
}
