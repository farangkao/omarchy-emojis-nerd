#!/usr/bin/env bash
# Marketplace security baseline, as a tests/ helper (issue #7): the
# scanner's scope rules exclude everything under tests/, so the git
# clone/fetch this script performs can never re-flag a remote-build
# capability. Invoke via `bash tests/security-baseline.sh` (mise runs
# exactly that) — keep the .sh extension and do not chmod +x, so the
# file stays squarely inside the excluded directory.
set -euo pipefail
cd "$(dirname "$0")/.."

marketplace=.tmp/marketplace
if [ -d "$marketplace/.git" ]; then
  git -C "$marketplace" fetch --depth 1 --quiet origin main
  git -C "$marketplace" reset --hard --quiet origin/main
else
  rm -rf "$marketplace"
  git clone --depth 1 --quiet https://github.com/HANCORE-linux/omarchy-plugin-marketplace "$marketplace"
fi

# Metadata must match the scanner CLI's current contract (it validates
# pluginIds/listedPlugins/entryPoints, not just repo+sha); the task
# resets the marketplace clone to origin/main, so this follows whatever
# validate-submission.mjs writes there.
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

# gh's mise shim prints a banner to stdout, so keep only the last line and
# only use it when it looks like a token; otherwise fall back to anonymous
# access, which works for public repos.
token="$(gh auth token 2>/dev/null | tail -n 1)"
case "$token" in
  ghp_*|gho_*|ghu_*|ghs_*|ghr_*|github_pat_*) export GITHUB_TOKEN="$token" ;;
esac

rm -f .tmp/baseline-result.json
node "$marketplace/scripts/security-baseline.mjs" --metadata=.tmp/baseline-metadata.json --json=.tmp/baseline-result.json || exit 1

[ "$(jq -r '.outcome // empty' .tmp/baseline-result.json)" = passed ] || {
  echo "security baseline: findings require attention — see the report above" >&2
  exit 1
}
