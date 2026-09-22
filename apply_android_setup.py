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
# Compatible Android build versions
# ============================================================

# Updated Kotlin version to 1.9.23 to resolve Gradle plugin compatibility
KOTLIN_VERSION = "1.9.23"
AGP_VERSION = "8.1.0"
GRADLE_VERSION = "8.0"

# All Android library subprojects (including plugin packages like livekit_client)
# are forced to build against this compileSdk. Some plugins declare a compileSdk
# lower than what they actually need, which breaks on attrs added in newer
# Android versions (e.g. android:attr/lStar, added in API 31).
COMPILE_SDK = 34


# ============================================================
# Update Gradle Wrapper
# ============================================================

wrapper_path = Path("android/gradle/wrapper/gradle-wrapper.properties")

if wrapper_path.exists():
    wrapper = wrapper_path.read_text(encoding="utf-8")

    wrapper = re.sub(
        r"distributionUrl=.*",
        f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE_VERSION}-all.zip",
        wrapper,
    )

    wrapper_path.write_text(wrapper, encoding="utf-8")
    print(f"Gradle wrapper updated to {GRADLE_VERSION}")


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

    # Kotlin Gradle Plugin
    s = re.sub(
        r'(id\s*\(?\s*["\']org\.jetbrains\.kotlin\.android["\']\s*\)?\s*version\s*\(?\s*["\'])[^"\']+(["\'])',
        r"\g<1>" + KOTLIN_VERSION + r"\g<2>",
        s,
    )

    # Add Google Services plugin declaration using the correct syntax.
    if "com.google.gms.google-services" not in s:
        if path.suffix == ".kts":
            plugin_line = (
                f'    id("com.google.gms.google-services") '
                f'version "4.4.2" apply false'
            )
        else:
            plugin_line = (
                f'    id "com.google.gms.google-services" '
                f'version "4.4.2" apply false'
            )

        match = re.search(r'plugins\s*\{', s)
        if match:
            position = match.end()
            s = s[:position] + "\n" + plugin_line + s[position:]

    path.write_text(s, encoding="utf-8")
    print(f"{path}: AGP={AGP_VERSION}, Kotlin={KOTLIN_VERSION}")


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
    print(f"{path}: Android/Kotlin versions updated")


# ============================================================
# Force compileSdk on every subproject (fixes plugins like livekit_client
# that pin their own, older compileSdk and fail on newer resource attrs)
# ============================================================

groovy_override = f"""
subprojects {{
    afterEvaluate {{ proj ->
        if (proj.hasProperty('android')) {{
            proj.android {{
                compileSdkVersion {COMPILE_SDK}
                if (namespace == null) {{
                    namespace proj.group.toString()
                }}
            }}
        }}
    }}
}}
"""

kts_override = f"""
subprojects {{
    afterEvaluate {{
        extensions.findByName("android")?.let {{ ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            android.compileSdkVersion({COMPILE_SDK})
        }}
    }}
}}
"""

root_groovy = Path("android/build.gradle")
root_kts = Path("android/build.gradle.kts")

if root_groovy.exists():
    s = root_groovy.read_text(encoding="utf-8")
    if f"compileSdkVersion {COMPILE_SDK}" not in s:
        with root_groovy.open("a", encoding="utf-8") as f:
            f.write(groovy_override)
        print(f"{root_groovy}: compileSdk {COMPILE_SDK} override appended to subprojects")
    else:
        print(f"{root_groovy}: compileSdk override already present")
elif root_kts.exists():
    s = root_kts.read_text(encoding="utf-8")
    if f"compileSdkVersion({COMPILE_SDK})" not in s:
        with root_kts.open("a", encoding="utf-8") as f:
            f.write(kts_override)
        print(f"{root_kts}: compileSdk {COMPILE_SDK} override appended to subprojects")
    else:
        print(f"{root_kts}: compileSdk override already present")
else:
    print("WARNING: no root android/build.gradle(.kts) found to patch for compileSdk override")


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
print(f"compileSdk      : {COMPILE_SDK} (forced on all subprojects)")
print("==============================================")
print("Android setup completed successfully.")
