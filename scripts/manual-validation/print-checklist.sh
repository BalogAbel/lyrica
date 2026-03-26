#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Local-First Manual Validation Checklist

Use native Flutter targets as the required acceptance path for authenticated offline relaunch.
Browser relaunch remains a best-effort diagnostic path for this slice.

1. Online launch
   Expect the sign-in flow to succeed, the song list to load, and the list shell to show "Online. Songs are up to date."

2. Offline relaunch from cache
   On a native target, after fetching songs online, stop local Supabase, relaunch the app, and expect the cached song list and reader to remain usable with "Offline. Showing cached songs."
   In the browser, treat the same relaunch as diagnostic only because web auth session restore may not match native behavior.

3. Refresh failure while cached data remains visible
   With cached songs already present, trigger a refresh while the backend is unavailable and expect cached content to remain visible together with "Unable to refresh songs. Showing the last cached catalog."

4. Explicit sign-out removes cached authenticated access
   Sign out from the authenticated song list and expect the app to return to the sign-in screen without continued access to cached authenticated songs.
EOF
