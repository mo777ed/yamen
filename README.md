# Yemen Chat (يمن شات)

Arabic-first social voice-room app: real-time voice rooms with seats, live chat, virtual gifts and coins, VIP, levels,
friends & private messages, games, agencies/hosts, rankings, events, moderation and an in-app admin panel.

Flutter (Riverpod + GoRouter, Clean Architecture per feature) · Firebase (Auth, Firestore, RTDB, Storage, FCM, Functions) ·
LiveKit (WebRTC SFU) behind a swappable `VoiceService`.

> **Original design.** The visual identity (dark, purple/blue gradients, gold for premium, glass cards) and UX were
> designed for this project; no assets or layouts were copied from another app. Gift art/animations are *not included* -
> add your own (see "Content you must supply").

## Verification status (read this first)

| Check | Status |
|---|---|
| Cloud Functions TypeScript compiles (`npm run build`, strict) | Run - passes |
| Functions unit tests (XP curve/cap, ranking periods, roles) | Run - 7/7 pass |
| Localization: ar/en have identical keys + placeholders; every `tr()` key exists | Checked by script |
| Dart: brace balance, per-file import/symbol cross-check | Checked by script |
| `flutter analyze` / `flutter test` (Dart unit, widget, repository tests) | **Not run** - no Flutter SDK in the build sandbox. Tests are written; run them first. |
| Firestore rules tests (`functions/test/rules.test.js`) | **Not run** - needs the Firebase emulator (Java). |
| Real LiveKit / payments / push on devices | **Not run** - needs your keys and devices. |

Expect a first `flutter analyze` pass to surface a few small fixes (package-version drift, deprecations). Package
versions in `pubspec.yaml` were chosen for Flutter >= 3.24; run `flutter pub upgrade --major-versions` if needed.

## Architecture

```
Flutter app
  presentation (Riverpod providers + widgets)
  data (repositories) -> Firestore (reads/streams) | Cloud Functions (all sensitive writes) | VoiceService (audio)

Cloud Functions (TypeScript)  = the only writer of: wallets, gifts, XP, VIP, games, rankings, roles, bans, audit logs
LiveKit SFU                   = audio; tokens minted by the joinRoom function, permissions updated on seat changes
Realtime Database             = presence + typing indicator (cheap, auto-cleaned on disconnect)
```

Folder structure: `lib/core` (theme, routing, errors, services), `lib/shared` (models, widgets), `lib/features/<feature>/{data,presentation}`.
Features with real business logic are in `data/` repositories; the server is the source of truth, so `domain/` use-case
layers were intentionally not duplicated for thin CRUD features.

### Security model
- `firestore.rules`: clients cannot write `wallets`, `gift_transactions`, `user_levels`, `user_vip`, `game_sessions`, `rankings`, `audit_logs`, roles, ban status, room passwords (`rooms_private`), or room seats/members. Room chat writes are limited to `type: text`, <= 300 chars, by non-muted members.
- `sendGift`: one Firestore transaction (balance check, debit, credit, ledger, XP, host/agency split, room event) + idempotency key.
- `verifyPurchase`: receipt verified server-side (Google Play implemented; App Store needs your key - see `functions/src/economy.ts`), deduplicated by order id.
- `playGame`: RNG (`crypto.randomInt`), payout, daily loss limit and idempotency are server-side. Winnings are coins only.
- Roles via custom claims (`user, host, agency_manager, moderator, admin, super_admin`) + rate limiting + input validation + audit log on every admin action.
- App Check enabled in release builds; secrets only in Functions secrets / `.env` (never committed).
- Minimum age 13 enforced in `completeProfile`.

### Data model
See `firestore.rules` + `lib/shared/models/models.dart`. Main collections: `users`, `usernames`, `wallets/{uid}/transactions`,
`user_levels`, `user_vip`, `rooms/{id}/{seats,members,messages}`, `rooms_private`, `chats/{id}/messages`, `friends/{uid}/list`,
`friend_requests`, `follows`, `blocks`, `posts`, `gifts`, `gift_transactions`, `vip_levels`, `games`, `game_sessions`,
`agencies`, `agency_members`, `hosts`, `rankings/{type}_{period}_{id}/entries`, `events`, `banners`, `settings`, `reports`,
`notifications/{uid}/items`, `audit_logs`, `purchases`, `idempotency`, `rate_limits`. Indexes: `firestore.indexes.json`.

## Feature map

| Requirement | Where |
|---|---|
| Auth: phone+OTP, email, Google, Apple, delete account, change phone/email | `features/auth`, `settings/SecurityScreen`, `functions/src/auth.ts` |
| Home / Discover / Search / Room list | `features/home`, `features/discover`, `features/rooms` |
| Voice rooms: seats, speaking rings, owner/mod controls, password, hand-raise | `features/voice_room`, `functions/src/rooms.ts`, `core/services/voice` |
| Room chat: emoji, mentions, system/gift/join messages, delete/mute/ban | `voice_room/chat_widgets.dart`, `roomModeration` |
| Gifts + full-screen animation queue | `features/gifts`, `functions/src/gifts.ts` |
| Wallet, coin packages (IAP), transactions | `features/wallet`, `functions/src/economy.ts` |
| VIP, levels/XP, daily login | `wallet/vip_screen`, `levels_screen`, `auth.ts`, `economy.ts` |
| Profile, follow, friends, block, report | `features/profile`, `friends`, `reports` |
| Private chat: text, images, read receipts, typing, online | `features/messages` |
| Notifications + FCM | `features/notifications`, `core/services/push_service.dart`, `functions/src/lib/notify.ts` |
| Games (dice, wheel, RPS, number guess; server-authoritative) | `features/games`, `playGame` |
| Agencies, hosts, dashboard, rankings, events | `features/agencies`, `hosts`, `rankings`, `events` |
| Admin: stats, users/bans/roles, reports, wallet adjust, catalog editors, agencies, audit log | `features/admin`, `functions/src/admin.ts` |
| Arabic RTL + English, dark (default) + light | `l10n/`, `assets/l10n/*.json`, `core/theme` |
| Offline: cached rooms/profiles/settings, offline banner | Firestore persistence (`main.dart`), `OfflineBanner` |

## Setup

Prerequisites: Flutter >= 3.24, Node 20, Firebase CLI, a Firebase project (Blaze plan for Functions), a LiveKit Cloud project (or self-hosted).

```bash
./tool/bootstrap.sh                 # flutter create, pub get, functions build
firebase use --add
flutterfire configure               # writes lib/firebase_options.dart
# apply docs/PLATFORM_SETUP.md
```

Firebase console: enable Authentication providers (Phone, Email/Password, Google, Apple), create Firestore (choose a location
close to your users), Realtime Database, Storage, enable App Check (Play Integrity / App Attest), Cloud Messaging.

### Where secrets/keys go
| Item | Location |
|---|---|
| LiveKit API key/secret | `firebase functions:secrets:set LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` |
| LiveKit URL, region, package names | `functions/.env` (copy from `functions/.env.example`) |
| LiveKit webhook | LiveKit dashboard -> Webhooks -> `https://<region>-<project>.cloudfunctions.net/livekitWebhook` (frees seats when someone drops) |
| Google Play verification | Grant the Functions service account access in Play Console (no key file) |
| App Store verification | Implement `verifyAppStore()` in `functions/src/economy.ts` with your App Store Connect key (use `@apple/app-store-server-library`); store the key as a Functions secret |
| Client config | `.env` (non-secret) and `lib/firebase_options.dart` (generated) |

### Run locally with emulators
```bash
cd functions && npm run serve            # auth, functions, firestore, database
# .env: USE_FIREBASE_EMULATOR=true and EMULATOR_HOST=10.0.2.2 (Android emulator) or 127.0.0.1 (iOS sim)
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-yemenchat node tool/seed.js
flutter run
```
(`joinRoom` needs LiveKit credentials even in the emulator; put them in `functions/.secret.local`.)

### Tests
```bash
flutter test                             # unit + widget + repository (fake Firestore)
cd functions && npm test                 # functions unit tests
cd functions && npm run test:rules       # rules tests (needs emulator + Java)
```

## Deployment order
1. `firebase deploy --only firestore,database,storage` (rules + indexes; indexes take minutes to build)
2. Set secrets, fill `functions/.env`, `firebase deploy --only functions`
3. Configure the LiveKit webhook URL
4. `node tool/seed.js` (gifts, VIP levels, games, economy, coin packages)
5. Create your first admin: sign up in the app, then in Firebase console -> Authentication copy the uid and run in a
   Node shell with Admin SDK: `admin.auth().setCustomUserClaims(uid, {role:'super_admin'})` and set `users/{uid}.role = 'super_admin'`. After that, manage roles from the in-app Admin panel.
6. Build release: `flutter build appbundle` / `flutter build ipa`, upload to the stores.

## Economy defaults (edit in `settings/economy`)
Receiver earns `diamondRate` (0.5) of a gift's list price in diamonds (agency commission is taken from that share);
VIP gift discount capped at 50%; XP daily cap 3000; game daily loss limit 50,000 coins; rate limits on every callable.

## Content you must supply
- Gift icons/animations (Lottie/Rive JSON, PNG) you have the rights to -> Admin panel -> Gifts (`iconUrl`, `animationUrl`).
- Fonts: the theme uses Google Fonts (Cairo) at runtime; bundle the font files under `assets/fonts` for fully offline first launch.
- App icon/splash, Privacy Policy and Terms pages.

## Known limitations / next steps
- Not implemented: voice messages in private chat (marked optional), minimized "floating room" mini-player, cash-out of diamonds, a separate Flutter-Web admin (the admin panel lives inside the app behind role guards), full-text search (prefix search only; add Typesense/Algolia for scale), iOS receipt verification (needs your keys), IP/device abuse detection (needs a legal/technical decision; the audit log + rate limits are the hooks).
- Custom-scheme deep links (`yemenchat://`) are not routed; use the https App Links / Universal Links.
- Chat and presence at very large scale will be your main cost centre; watch Firestore reads (room chat `limit(60)`) and consider moving hot chat to RTDB or a dedicated service.
- Have the rules tests and a security review done before launch; moderation staffing matters as much as code for voice-chat apps.
