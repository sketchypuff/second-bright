#!/bin/bash
# Prints the release notes for one version: its CHANGELOG.md section, followed
# by the install steps every release needs.
#
#     Scripts/release-notes.sh 1.1
#
# The install steps are appended here rather than written into CHANGELOG.md
# because they are the same every time and have nothing to do with what changed.
# They stay until the app is notarized, at which point the warning they explain
# stops happening and this block should go.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: release-notes.sh <version>   e.g. release-notes.sh 1.1}"
CHANGELOG="CHANGELOG.md"

# Everything between this version's heading and the next one. Missing is fatal:
# publishing a release with an empty body is worse than not publishing.
NOTES="$(awk -v want="## $VERSION" '
    $0 == want { found = 1; next }
    found && /^## / { exit }
    found { print }
' "$CHANGELOG")"

if [ -z "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ]; then
    echo "error: no '## $VERSION' section in $CHANGELOG" >&2
    exit 1
fi

# Trim blank lines from both ends so the spacing doesn't depend on how the
# section happened to be laid out.
printf '%s\n' "$NOTES" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}'

cat <<'INSTALL'

## Install

1. Download the `.dmg` below.
2. Open it and drag **SecondBright** onto the **Applications** folder.
3. Open SecondBright from Applications. macOS will refuse the first time,
   because this app is not signed with a paid Apple Developer certificate. Click
   **Done**, then open **System Settings › Privacy & Security**, scroll to the
   bottom, and click **Open Anyway**.

Step 3 happens once. After that it opens normally, including at login.

Requires macOS 14 or later, on a Mac with Apple Silicon.
INSTALL
