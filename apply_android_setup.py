import re
from pathlib import Path


# ============================================================
# Android Manifest
# ============================================================

manifest_path = Path("android/app/src/main/AndroidManifest.xml")

if manifest_path.exists():
    manifest = manifest_path.read_text(encoding="utf-8")

    perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
"""

    if "RECORD_AUDIO" not in manifest:
        manifest = manifest.replace(
            "<application",
            perms + "    <application",
            1,
        )
        manifest_path.write_text(manifest, encoding="utf-8")
        print("AndroidManifest.xml: permissions added")
    else:
        print("AndroidManifest.xml: permissions already present")


# ============================================================
# NOTE ON VERSIONS
# ============================================================
# This script intentionally does NOT force a specific Gradle / Android
# Gradle Plugin (AGP) / Kotlin version anymore. `flutter create` (run in
# the workflow before this script) already generates a project pinned to
# versions that are tested and compatible with the installed Flutter SDK.
#
# An earlier version of this script forced Gradle down to 8.0 and AGP to
# 8.1.0. That broke Flutter's OWN internal build-tooling project (a small
# Gradle project bundled inside the Flutter SDK, unrelated to our app),
# which failed to resolve an old transitive dependency
# (com.squareup:javawriter:2.5.0) that used to live on the now-shut-down
# JCenter repository - producing:
#   "Could not find com.squareup:javawriter:2.5.0 ... project :gradle"
# If you ever see that error again, it means something is once again
# overriding Gradle/AGP away from Flutter's own defaults - remove it.


# All Android library subprojects (including plugin packages like livekit_client)
# are additionally forced to build against this compileSdk. Some plugins declare
# their own, older compileSdk that lacks newer resource attrs (e.g.
# android:attr/lStar, added in API 31). This is independent of the AGP/Gradle
# version and safe to keep.
COMPILE_SDK = 34


# ============================================================
# Force compileSdk on every subproject (fixes plugins like livekit_client
# that pin their own, older compileSdk and fail on newer resource attrs)
# ============================================================
#
# IMPORTANT: the default Flutter root build.gradle ends with a block like:
#
#     subprojects {
#         project.evaluationDependsOn(':app')
#     }
#
# which forces immediate evaluation of :app. If we register our afterEvaluate
# hook in a SEPARATE subprojects{} block placed after that one, Gradle fails
# with "Cannot run Project.afterEvaluate(Closure) when the project is
# already evaluated." So instead of appending a new block, we inject our
# hook as the FIRST statement inside the EXISTING subprojects{} block (or
# create one if none exists), which guarantees it is registered before
# evaluationDependsOn forces evaluation.
#
# This is a secondary safety net; patch_plugin_compilesdk.py (run after
# `flutter pub get`) is the primary, more reliable fix for livekit_client
# specifically, since it edits the plugin's own build.gradle directly.

groovy_inject = (
    "\n    afterEvaluate {\n"
    "        if (hasProperty('android')) {\n"
    "            android {\n"
    f"                compileSdkVersion {COMPILE_SDK}\n"
    "                if (namespace == null) {\n"
    "                    namespace group.toString()\n"
    "                }\n"
    "            }\n"
    "        }\n"
    "    }\n"
)

kts_inject = (
    "\n    afterEvaluate {\n"
    "        extensions.findByName(\"android\")?.let { ext ->\n"
    "            val android = ext as com.android.build.gradle.BaseExtension\n"
    f"            android.compileSdkVersion({COMPILE_SDK})\n"
    "        }\n"
    "    }\n"
)


def inject_into_subprojects(text: str, inject: str, marker: str) -> str:
    if marker in text:
        return text  # already applied
    match = re.search(r"subprojects\s*\{", text)
    if match:
        pos = match.end()
        return text[:pos] + inject + text[pos:]
    # No existing subprojects{} block: append a new, self-contained one.
    return text + "\nsubprojects {" + inject + "}\n"


root_groovy = Path("android/build.gradle")
root_kts = Path("android/build.gradle.kts")

if root_groovy.exists():
    s = root_groovy.read_text(encoding="utf-8")
    marker = f"compileSdkVersion {COMPILE_SDK}"
    new_s = inject_into_subprojects(s, groovy_inject, marker)
    if new_s != s:
        root_groovy.write_text(new_s, encoding="utf-8")
        print(f"{root_groovy}: compileSdk {COMPILE_SDK} override injected into subprojects{{}}")
    else:
        print(f"{root_groovy}: compileSdk override already present")
elif root_kts.exists():
    s = root_kts.read_text(encoding="utf-8")
    marker = f"compileSdkVersion({COMPILE_SDK})"
    new_s = inject_into_subprojects(s, kts_inject, marker)
    if new_s != s:
        root_kts.write_text(new_s, encoding="utf-8")
        print(f"{root_kts}: compileSdk {COMPILE_SDK} override injected into subprojects{{}}")
    else:
        print(f"{root_kts}: compileSdk override already present")
else:
    print("WARNING: no root android/build.gradle(.kts) found to patch for compileSdk override")


# ============================================================
# Firebase Google Services Plugin + minSdk
# ============================================================

app_files = [
    Path("android/app/build.gradle.kts"),
    Path("android/app/build.gradle"),
]

for path in app_files:
    if not path.exists():
        continue

    s = path.read_text(encoding="utf-8")

    # minSdk = 23
    s = re.sub(
        r"minSdk\s*=\s*flutter\.minSdkVersion",
        "minSdk = 23",
        s,
    )

    s = re.sub(
        r"minSdkVersion\s+flutter\.minSdkVersion",
        "minSdkVersion 23",
        s,
    )

    # Apply Firebase plugin if not already present.
    if "com.google.gms.google-services" not in s:
        if path.suffix == ".kts":
            marker = 'id("dev.flutter.flutter-gradle-plugin")'
            replacement = (
                marker
                + '\n    id("com.google.gms.google-services")'
            )
        else:
            marker = "id 'dev.flutter.flutter-gradle-plugin'"
            replacement = (
                marker
                + "\n    id 'com.google.gms.google-services'"
            )

        if marker in s:
            s = s.replace(marker, replacement, 1)

    path.write_text(s, encoding="utf-8")
    print(f"{path}: updated")


# Register the google-services Gradle plugin declaration (version resolved
# automatically by Flutter's own dependency management; we just need the
# plugin id declared so `apply plugin` / `id(...)` above can find it).
settings_files = [
    Path("android/settings.gradle.kts"),
    Path("android/settings.gradle"),
]

for path in settings_files:
    if not path.exists():
        continue

    s = path.read_text(encoding="utf-8")

    if "com.google.gms.google-services" not in s:
        if path.suffix == ".kts":
            plugin_line = '    id("com.google.gms.google-services") version "4.4.2" apply false'
        else:
            plugin_line = '    id "com.google.gms.google-services" version "4.4.2" apply false'

        match = re.search(r'plugins\s*\{', s)
        if match:
            position = match.end()
            s = s[:position] + "\n" + plugin_line + s[position:]
            path.write_text(s, encoding="utf-8")
            print(f"{path}: google-services plugin declared")
        else:
            print(f"WARNING: {path} has no plugins {{}} block; could not declare google-services plugin")
    else:
        print(f"{path}: google-services plugin already declared")


# ============================================================
# Final checks
# ============================================================

print("")
print("==============================================")
print("Android build configuration")
print("==============================================")
print("Gradle / AGP / Kotlin : left at flutter create's own defaults")
print(f"compileSdk (forced)   : {COMPILE_SDK} (subprojects override + patch_plugin_compilesdk.py)")
print("==============================================")
print("Android setup completed successfully.")
