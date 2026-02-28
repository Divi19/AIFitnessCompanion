# AI Fitness Companion — Full Setup Guide (Windows)

> **Note:** macOS can develop for both iOS and Android. Windows can only develop for Android.

---

## Table of Contents
1. [Install VS Code Extensions](#1-install-vs-code-extensions)
2. [Install Java](#2-install-java)
3. [Install Android Studio & Android SDK](#3-install-android-studio--android-sdk)
4. [Install Flutter SDK](#4-install-flutter-sdk)
5. [Verify Everything with Flutter Doctor](#5-verify-everything-with-flutter-doctor)
6. [Install Node.js & Firebase CLI](#6-install-nodejs--firebase-cli)
7. [Clone the Flutter Project](#7-clone-the-flutter-project)
8. [Connect Flutter to Firebase](#8-connect-flutter-to-firebase)
9. [Configure API Keys](#9-configure-api-keys)
10. [First Run](#10-first-run)

---

## 1. Install VS Code Extensions

Open VS Code, go to the Extensions panel (`Ctrl+Shift+X`) and install:

- **Flutter** (by Dart Code) — also auto-installs the Dart extension
- **Dart** (by Dart Code)

> Fully restart VS Code after installing both extensions before continuing.

---

## 2. Install Java

First confirm you have Git installed:
```bash
git --version
```
If not, download Git from https://git-scm.com first.

Android development requires Java JDK 17.

1. Download JDK 17 from https://adoptium.net — choose **Temurin 17 LTS, Windows x64 .msi**
2. Run the installer — check the box to **Set JAVA_HOME** during installation
3. Open a new Command Prompt and verify:
```bash
java --version
```

> **Important:** After any PATH or environment variable change on Windows, always open a **brand-new** Command Prompt window before running verification commands — otherwise the change will not be picked up.

---

## 3. Install Android Studio & Android SDK

Android Studio provides the Android emulator and SDK tools needed by Flutter.

1. Download Android Studio from https://developer.android.com/studio
2. Run the installer and follow the setup wizard:
   - Install type: **Standard**
   - Accept all license agreements
   - Let it download the Android SDK, emulator, and build tools (this takes a while)

### Verify Android SDK Path
Go to:
```
Control Panel → System → Advanced System Settings → Environment Variables
```
Confirm `ANDROID_HOME` points to:
```
C:\Users\<YourName>\AppData\Local\Android\Sdk
```
If it's missing, add it manually as a system environment variable.

### Install Android SDK Command-line Tools
This step is often missed and causes `flutter doctor` to fail:

1. Open Android Studio → **SDK Manager** → **SDK Tools** tab
2. Check **Android SDK Command-line Tools**
3. Click **Apply**

### Create a Virtual Device (Emulator)

Inside Android Studio:

1. Go to **More Actions → Virtual Device Manager**
2. Click **Create Device**
3. Select **Pixel 7 → Next**
4. Download and select **API 34 (Android 14) → Next → Finish**
5. Press the Play button to start the emulator and confirm it boots

### Accept Android Licenses
```bash
flutter doctor --android-licenses
# Press y to accept each one
```

---

## 4. Install Flutter SDK

1. Download the latest Flutter SDK zip from https://docs.flutter.dev/get-started/install/windows
2. Extract it to a folder with **no spaces** in the path, e.g. `C:\dev\flutter` (not Program Files)
3. Add Flutter to your system PATH:
   - Search for **"Environment Variables"** in the Start menu
   - Under **User variables**, find **Path** and click **Edit**
   - Click **New** and add: `C:\dev\flutter\bin`
   - Click OK on all dialogs

4. Close and reopen your terminal, then verify:
```bash
flutter --version
```
You should see output like `Flutter 3.x.x · channel stable`.

---

## 5. Verify Everything with Flutter Doctor

This is the most important step. Run:
```bash
flutter doctor
```

You are aiming for:
```
[✓] Flutter (Channel stable, 3.x.x)
[✓] Android toolchain - develop for Android devices
[✓] VS Code (version x.x.x)
[✓] Connected device
[✓] Network resources
```

**Common issues and fixes:**

| Issue | Fix |
|-------|-----|
| Android license status unknown | Run `flutter doctor --android-licenses` and accept all |
| cmdline-tools component is missing | Android Studio → SDK Manager → SDK Tools → check Android SDK Command-line Tools → Apply |
| Java not found | Confirm Java is installed and `JAVA_HOME` is set |

> Do not proceed until `flutter doctor` shows no `[✗]` errors. Warnings marked `[!]` are usually fine.

---

## 6. Install Node.js & Firebase CLI

Node.js is required for the Firebase CLI.

1. Download the LTS installer from https://nodejs.org
2. Run the installer — accept all defaults
3. Open a new terminal and verify:
```bash
node --version
npm --version
```

### Install Firebase CLI
```bash
npm install -g firebase-tools
```

Log in with the **same Google account** used for the Firebase project:
```bash
firebase login
```
A browser window will open — sign in with the team's Google account.

### Install FlutterFire CLI
```bash
dart pub global activate flutterfire_cli
```

Then add this to your Windows **User PATH** environment variable:
```
C:\Users\<YourName>\AppData\Local\Pub\Cache\bin
```

Verify:
```bash
flutterfire --version
```

---

## 7. Clone the Flutter Project

Open your terminal, navigate to where you want to store the project, and run:
```bash
git clone <project-url>
cd ai-fitness-companion
```

Fetch all Flutter dependencies:
```bash
flutter pub get
```

---

## 8. Connect Flutter to Firebase

Inside the `ai-fitness-companion` project folder, run:
```bash
flutterfire configure
```

- Select the **ai-fitness-companion** Firebase project from the list
- Use **spacebar** to select **android**, then press **Enter**

FlutterFire will automatically:
- Download `google-services.json` into `android/app/`
- Generate `lib/firebase_options.dart`

> **If the project doesn't appear in the list**, your Google account has not been added to the Firebase project yet. Contact the project owner to be added before attempting this step.

> **Never manually edit** `lib/firebase_options.dart`. If you need to regenerate it, re-run `flutterfire configure`.

---

## 9. Configure API Keys

A `.env.example` file is included in the project root. Copy it and fill in your key:
```bash
copy .env.example .env
```

Open `.env` and replace the placeholder with your actual Gemini API key:
```
GEMINI_API_KEY=your_actual_key_here
```

> Contact the project owner if you need the API key value. Never commit the `.env` file — it is already listed in `.gitignore`.

---

## 10. First Run

Start your emulator (if not already running from Step 3), then check Flutter can see it:
```bash
flutter devices
```

You should see your emulator listed. Then launch the app:
```bash
flutter run --dart-define-from-file=.env
```

The first build will take a few minutes. If the app appears on the emulator, you are fully set up.

---

> **Still stuck?** Contact the project owner directly. Common first-build issues on Windows include Gradle permission errors — if the build fails, try running `cd android && gradlew clean && cd ..` before `flutter run --dart-define-from-file=.env`.