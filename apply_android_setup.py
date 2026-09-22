import re
import sys
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
# Versions
# ============================================================

KOTLIN_VERSION = "2.1.0"
AGP_VERSION = "7.3.1"
GRADLE_VERSION = "7.6.3"


# ============================================================
# Update Gradle Wrapper
# ============================================================

wrapper_path = Path(
    "android/gradle/wrapper/gradle-wrapper.properties"
)

if wrapper_path.exists():
    wrapper = wrapper_path.read_text(encoding="utf-8")

    wrapper = re.sub(
        r"distributionUrl=.*",
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-7.6.3-all.zip",
        wrapper,
    )

    wrapper_path.write_text(wrapper, encoding="utf-8")

    print(
        f"Gradle wrapper updated to {GRADLE_VERSION}"
    )


# ============================================================
# Update Android Gradle Plugin + Kotlin
# ============================================================

settings_files = [
    Path("android/settings.gradle.kts"),
    Path("android/settings.gradle"),
]

for path in settings_files:

    if not path.exists():
        continue

    s = path.read_text(encoding="utf-8")

    # Android Gradle Plugin
    s = re.sub(
        r'(id\s*\(?\s*["\']com\.android\.application["\']\s*\)?\s*version\s*\(?\s*["\'])[^"\']+(["\'])',
        r"\g<1>" + AGP_VERSION + r"\g<2>",
        s,
    )

    # Kotlin
    s = re.sub(
        r'(id\s*\(?\s*["\']org\.jetbrains\.kotlin\.android["\']\s*\)?\s*version\s*\(?\s*["\'])[^"\']+(["\'])',
        r"\g<1>" + KOTLIN_VERSION + r"\g<2>",
        s,
    )

    path.write_text(s, encoding="utf-8")

    print(
        f"{path}: AGP={AGP_VERSION}, Kotlin={KOTLIN_VERSION}"
    )


# ============================================================
# Update old Groovy build.gradle projects
# ============================================================

build_files = [
    Path("android/build.gradle"),
    Path("android/build.gradle.kts"),
]

for path in build_files:

    if not path.exists():
        continue

    s = path.read_text(encoding="utf-8")

    # Kotlin version
    s = re.sub(
        r"(ext\.kotlin_version\s*=\s*['\"])[^'\"]+(['\"])",
        r"\g<1>" + KOTLIN_VERSION + r"\g<2>",
        s,
    )

    # Android Gradle Plugin
    s = re.sub(
        r"(com\.android\.tools\.build:gradle:)[0-9.]+",
        r"\g<1>" + AGP_VERSION,
        s,
    )

    path.write_text(s, encoding="utf-8")

    print(
        f"{path}: Android/Kotlin versions updated"
    )


# ============================================================
# Firebase Google Services Plugin
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

    # Firebase plugin
    if "com.google.gms.google-services" not in s:

        if path.name.endswith(".kts"):

            s = s.replace(
                'id("dev.flutter.flutter-gradle-plugin")',
                'id("dev.flutter.flutter-gradle-plugin")\n'
                '    id("com.google.gms.google-services")',
                1,
            )

        else:

            s = s.replace(
                "apply plugin: 'dev.flutter.flutter-gradle-plugin'",
                "apply plugin: 'dev.flutter.flutter-gradle-plugin'\n"
                "apply plugin: 'com.google.gms.google-services'",
                1,
            )

    path.write_text(s, encoding="utf-8")

    print(f"{path}: updated")


# ============================================================
# Google Services plugin declaration
# ============================================================

settings_files = [
    Path("android/settings.gradle.kts"),
    Path("android/settings.gradle"),
]

for path in settings_files:

    if not path.exists():
        continue

    s = path.read_text(encoding="utf-8")

    if "com.google.gms.google-services" not in s:

        if "pluginManagement" in s:

            # Add plugin to plugins block if possible
            match = re.search(
                r"plugins\s*\{",
                s,
            )

            if match:

                position = match.end()

                plugin_line = (
                    '\n    id "com.google.gms.google-services" '
                    'version "4.4.2" apply false'
                )

                s = (
                    s[:position]
                    + plugin_line
                    + s[position:]
                )

                path.write_text(
                    s,
                    encoding="utf-8",
                )

                print(
                    f"{path}: Google Services plugin declared"
                )


# ============================================================
# Final checks
# ============================================================

print("")
print("==============================================")
print("Android build configuration")
print("==============================================")
print(f"AGP version     : {AGP_VERSION}")
print(f"Kotlin version  : {KOTLIN_VERSION}")
print(f"Gradle version  : {GRADLE_VERSION}")
print("==============================================")
print("Android setup completed successfully.")
