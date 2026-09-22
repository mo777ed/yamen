"""
Generates lib/firebase_options.dart (Android-only) directly from
android/app/google-services.json, so `flutterfire configure` is never needed
in CI. Run this AFTER google-services.json has been written and BEFORE
`flutter build apk`.
"""
import json
import os
import sys

GOOGLE_SERVICES_PATH = "android/app/google-services.json"
OUTPUT_PATH = "lib/firebase_options.dart"

def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)

if not os.path.exists(GOOGLE_SERVICES_PATH):
    fail(f"{GOOGLE_SERVICES_PATH} not found")

with open(GOOGLE_SERVICES_PATH, "r", encoding="utf-8") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as e:
        fail(f"{GOOGLE_SERVICES_PATH} is not valid JSON: {e}")

project_info = data.get("project_info", {})
project_id = project_info.get("project_id")
messaging_sender_id = project_info.get("project_number")
storage_bucket = project_info.get("storage_bucket")

clients = data.get("client", [])
if not clients:
    fail("No 'client' entries found in google-services.json")

# Prefer the client whose package_name matches the app's applicationId, if we
# can find it; otherwise fall back to the first (and usually only) client.
target_package = os.environ.get("ANDROID_PACKAGE_NAME", "").strip()
chosen = None
if target_package:
    for c in clients:
        pkg = c.get("client_info", {}).get("android_client_info", {}).get("package_name")
        if pkg == target_package:
            chosen = c
            break
if chosen is None:
    chosen = clients[0]

app_id = chosen.get("client_info", {}).get("mobilesdk_app_id")
api_keys = chosen.get("api_key", [])
api_key = api_keys[0].get("current_key") if api_keys else None

missing = [name for name, val in [
    ("appId", app_id),
    ("apiKey", api_key),
    ("projectId", project_id),
    ("messagingSenderId", messaging_sender_id),
] if not val]
if missing:
    fail(f"Could not extract required field(s) from google-services.json: {', '.join(missing)}")

storage_bucket_line = (
    f"    storageBucket: '{storage_bucket}',\n" if storage_bucket else ""
)

dart_content = f"""// GENERATED FILE. DO NOT EDIT.
// Auto-generated in CI from android/app/google-services.json.
// This intentionally covers Android only.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {{
  static FirebaseOptions get currentPlatform {{
    if (kIsWeb) {{
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }}
    switch (defaultTargetPlatform) {{
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }}
  }}

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '{api_key}',
    appId: '{app_id}',
    messagingSenderId: '{messaging_sender_id}',
    projectId: '{project_id}',
{storage_bucket_line}  );
}}
"""

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
    f.write(dart_content)

print(f"{OUTPUT_PATH}: generated from {GOOGLE_SERVICES_PATH} (project_id={project_id})")
