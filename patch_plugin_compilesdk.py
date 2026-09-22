"""
Directly patches compileSdkVersion inside Flutter plugin packages fetched by
`flutter pub get` (pub cache), instead of relying on a root-level
subprojects.afterEvaluate override. Some plugins (livekit_client and its
dependencies included) declare their own, older compileSdkVersion in their
Android build.gradle(.kts). If that value is lower than what a resource they
use requires (e.g. android:attr/lStar, added in API 31), AAPT2 fails with
"resource android:attr/lStar not found" even if the app module itself
targets a newer compileSdk - each Android library subproject compiles its
resources against ITS OWN declared compileSdk.

Run this AFTER `flutter pub get` (so the packages actually exist on disk).
"""
import os
import re
from pathlib import Path

TARGET_SDK = 34

pub_cache = os.environ.get("PUB_CACHE") or str(Path.home() / ".pub-cache")
search_roots = [
    Path(pub_cache) / "hosted" / "pub.dev",
    Path(pub_cache) / "hosted" / "pub.dartlang.org",  # older pub cache layout
]

groovy_compile_sdk = re.compile(r"compileSdkVersion\s+(\d+)")
kts_compile_sdk_a = re.compile(r"compileSdk\s*=\s*(\d+)")
kts_compile_sdk_b = re.compile(r"compileSdkVersion\((\d+)\)")

patched = []

for root in search_roots:
    if not root.exists():
        continue
    for build_file in root.glob("*/android/build.gradle"):
        text = build_file.read_text(encoding="utf-8")
        m = groovy_compile_sdk.search(text)
        if m and int(m.group(1)) < TARGET_SDK:
            new_text = groovy_compile_sdk.sub(f"compileSdkVersion {TARGET_SDK}", text)
            build_file.write_text(new_text, encoding="utf-8")
            patched.append((build_file, m.group(1), TARGET_SDK))

    for build_file in root.glob("*/android/build.gradle.kts"):
        text = build_file.read_text(encoding="utf-8")
        new_text = text
        changed = False
        m = kts_compile_sdk_a.search(new_text)
        if m and int(m.group(1)) < TARGET_SDK:
            new_text = kts_compile_sdk_a.sub(f"compileSdk = {TARGET_SDK}", new_text)
            changed = True
        m2 = kts_compile_sdk_b.search(new_text)
        if m2 and int(m2.group(1)) < TARGET_SDK:
            new_text = kts_compile_sdk_b.sub(f"compileSdkVersion({TARGET_SDK})", new_text)
            changed = True
        if changed:
            build_file.write_text(new_text, encoding="utf-8")
            patched.append((build_file, "?", TARGET_SDK))

if patched:
    print(f"Patched compileSdk to {TARGET_SDK} in {len(patched)} plugin(s):")
    for f, old, new in patched:
        print(f"  {f}  ({old} -> {new})")
else:
    print(f"No plugin build.gradle(.kts) needed a compileSdk bump (pub cache: {pub_cache}).")
    print("If livekit_client still fails, check that PUB_CACHE matches what `flutter pub get` used.")
