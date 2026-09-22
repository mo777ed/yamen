#!/usr/bin/env bash
# One-time project bootstrap. Run from the repository root.
set -euo pipefail

command -v flutter >/dev/null || { echo "Flutter SDK not found (need >= 3.24)"; exit 1; }
command -v firebase >/dev/null || echo "WARNING: firebase-tools not found (npm i -g firebase-tools)"

# 1) Generate android/ and ios/ runners (keeps existing lib/ and pubspec.yaml).
flutter create --org com.yemenchat --project-name yemen_chat --platforms=android,ios .

# 2) Client config
[ -f .env ] || cp .env.example .env
flutter pub get

# 3) Functions
( cd functions && npm install && npm run build )

cat <<'MSG'

Next steps (see README.md -> "Setup"):
  1. firebase login && firebase use --add        # pick/create your Firebase project
  2. dart pub global activate flutterfire_cli && flutterfire configure
  3. Apply docs/PLATFORM_SETUP.md to android/ and ios/ (permissions, minSdk, capabilities)
  4. firebase deploy --only firestore,database,storage
  5. firebase functions:secrets:set LIVEKIT_API_KEY && firebase functions:secrets:set LIVEKIT_API_SECRET
  6. cp functions/.env.example functions/.env  (fill LIVEKIT_URL, package names)
  7. firebase deploy --only functions
  8. node tool/seed.js
MSG
