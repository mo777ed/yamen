# Platform setup (Android + iOS)

`tool/bootstrap.sh` runs `flutter create` which generates `android/` and `ios/`. Then apply the following.

## Android

**`android/app/build.gradle(.kts)`**
```
minSdk = 23            // Firebase + LiveKit
targetSdk = 34 (or current Play requirement)
```
Apply the plugins Firebase asks for (`com.google.gms.google-services`, `com.google.firebase.crashlytics`) and put
`google-services.json` in `android/app/` (created by `flutterfire configure` / Firebase console).
Add your **debug and release SHA-1 / SHA-256** fingerprints in Firebase (needed for Phone Auth, Google sign-in, Play Integrity/App Check).

**`android/app/src/main/AndroidManifest.xml`** (inside `<manifest>`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```
Inside the main `<activity>` add the App Links filter (so `https://yemenchat.app/room/<id>` opens the room):
```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="https" android:host="yemenchat.app" android:pathPrefix="/room"/>
  <data android:scheme="https" android:host="yemenchat.app" android:pathPrefix="/profile"/>
</intent-filter>
```
Host `https://yemenchat.app/.well-known/assetlinks.json` with your package name + release SHA-256.

**Play Console**: create the consumable products used in `settings/coin_packages` (`coins_100`, ...), then grant the
Cloud Functions service account access (Users & permissions -> "View financial data" + "Manage orders").

## iOS

**`ios/Podfile`**: `platform :ios, '13.0'`

**`ios/Runner/Info.plist`**
```xml
<key>NSMicrophoneUsageDescription</key><string>Yemen Chat needs the microphone so you can talk in voice rooms.</string>
<key>NSPhotoLibraryUsageDescription</key><string>Choose photos for your profile, rooms and chats.</string>
<key>NSCameraUsageDescription</key><string>Take photos for your profile and chats.</string>
<key>UIBackgroundModes</key>
<array><string>audio</string><string>remote-notification</string></array>
<!-- Phone Auth reCAPTCHA callback: paste REVERSED_CLIENT_ID from GoogleService-Info.plist -->
<key>CFBundleURLTypes</key>
<array><dict><key>CFBundleURLSchemes</key><array><string>com.googleusercontent.apps.XXXX</string></array></dict></array>
```
**Xcode capabilities**: Push Notifications, Background Modes (Audio, Remote notifications), Sign in with Apple,
In-App Purchase, Associated Domains (`applinks:yemenchat.app`).
Upload your **APNs auth key** in Firebase console -> Cloud Messaging. Host `apple-app-site-association` at
`https://yemenchat.app/.well-known/apple-app-site-association`.

## Store policy checklist for a user-generated-content voice app
- Report user / room / message, block user, and in-app **account deletion** are implemented (Apple 1.2 / 5.1.1(v), Google UGC + account deletion policies).
- Coins are sold only through Apple/Google in-app purchase. Do **not** add external payment links for coins.
- Games use non-cashable coins. Diamonds (earned from gifts) are *not* convertible in this codebase; adding cash-out for
  hosts is a legal/tax/payments project (KYC, payout provider, local regulations) and needs professional advice first.
- Provide a public Privacy Policy and Terms URL and fill the store data-safety / privacy forms.
- Age: the app enforces a minimum age of 13 at sign-up; consider 17+/18+ ratings depending on your moderation level.
