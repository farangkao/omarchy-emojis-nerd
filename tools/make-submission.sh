#!/usr/bin/env bash
# Writes the omarchyplugins.com submission issue body to /tmp and prints it.
# The format is defined by HANCORE-linux/omarchy-plugin-marketplace
# SUBMISSION.md; all six headings must stay in this exact order.
set -euo pipefail

BODY=/tmp/omarchy-plugin-submission.md

cat >"$BODY" <<'EOF'
### Repository URL

https://github.com/farangkao/omarchy-emojis-nerd

### Category

Productivity

### Tags

launcher, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Replaces the built-in emoji picker via omarchy.clonedFrom routing; the
SUPER+CTRL+E binding keeps working and removal restores the built-in picker.
Requires Omarchy with shell plugin support. Ships two datasets: Omarchy
emojis (MIT) and Nerd Fonts glyphnames (MIT); no fonts are bundled.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
EOF

cat "$BODY"
echo
echo "Review the body above, then create the issue with: mise run publish"
