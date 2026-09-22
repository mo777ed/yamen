import re, sys

manifest_path = "android/app/src/main/AndroidManifest.xml"
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = f.read()

perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
"""
if "RECORD_AUDIO" not in manifest:
    manifest = manifest.replace("<application", perms + "    <application", 1)
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(manifest)
    print("AndroidManifest.xml: permissions added")
else:
    print("AndroidManifest.xml: permissions already present")

# minSdk -> 23, and add google-services plugin, for both Groovy and Kotlin DSL build files.
for path in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            s = f.read()
    except FileNotFoundError:
        continue

    s2 = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
    s2 = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", s2)

    if "com.google.gms.google-services" not in s2:
        if path.endswith(".kts"):
            s2 = s2.replace(
                'id("dev.flutter.flutter-gradle-plugin")',
                'id("dev.flutter.flutter-gradle-plugin")\n    id("com.google.gms.google-services")',
                1,
            )
        else:
            s2 = s2.replace(
                "apply plugin: 'dev.flutter.flutter-gradle-plugin'",
                "apply plugin: 'dev.flutter.flutter-gradle-plugin'\napply plugin: 'com.google.gms.google-services'",
                1,
            )

    if s2 != s:
        with open(path, "w", encoding="utf-8") as f:
            f.write(s2)
        print(f"{path}: updated")

# Register the google-services classpath at the project level.
for path in ["android/build.gradle.kts", "android/build.gradle", "android/settings.gradle.kts", "android/settings.gradle"]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            s = f.read()
    except FileNotFoundError:
        continue
    if "google-services" in s:
        print(f"{path}: google-services plugin already declared")
        continue
    if path.endswith("settings.gradle.kts") and "pluginManagement" in s:
        s2 = re.sub(
            r'(id\("dev\.flutter\.flutter-plugin-loader"\)[^\n]*\n)',
            r'\1    id("com.google.gms.google-services") version "4.4.2" apply false\n',
            s,
            count=1,
        )
        if s2 != s:
            with open(path, "w", encoding="utf-8") as f:
                f.write(s2)
            print(f"{path}: google-services plugin declared")
