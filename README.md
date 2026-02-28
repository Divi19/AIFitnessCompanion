# 📋 Project Overview - FitSense

# The AI-powered preventive health companion designed to combat Malaysia’s rising lifestyle-related health crisis.

## 🚨 Problem Statement

Urban Malaysia is facing a growing health crisis driven by sedentary lifestyles and poor health behaviour sustainability. According to the **National Health and Morbidity Survey 2023**:

- 1 in 3 Malaysian adults is physically inactive  
- 53.6% of Malaysian adults are overweight or obese  
- Physical inactivity increases the risk of cardiovascular disease, type 2 diabetes, obesity, and mental health disorders  

Existing fitness and nutrition solutions are fragmented, expensive, and fail to personalise to individual needs, resulting in high drop-off rates and minimal long-term behavioural change.

---

## 🌍 SDG Alignment

This project directly addresses **UN SDG 3 — Good Health and Well-Being**, specifically:

### 🎯 Target 3.4  
Reduce premature mortality from non-communicable diseases through prevention and promote mental health and well-being.  
Our app targets modifiable behavioural risk factors such as physical inactivity and poor diet that drive these diseases.

### 🎯 Target 3.8  
Achieve universal health coverage and access to quality health-care services.  
Our solution provides free, AI-powered preventive health guidance that was previously only affordable to a privileged few.

---

# 💡 Solution

**FitSense** is a free, all-in-one AI-powered mobile health companion built with **Flutter**.

Instead of juggling multiple paid apps, users get everything they need in one place:

- An evidence-based AI health chatbot grounded in verified medical literature via a RAG pipeline  
- A real-time AI fitness companion with pose detection, form correction, and injury-aware workout generation  
- A smart meal and snack tracker with AI photo recognition and barcode scanning  

The app is designed specifically for urban Malaysians aged 18–50, prioritising safety, inclusivity, affordability, and long-term habit formation over short-term aesthetics.

---

# ✨ Key Features

## 1️⃣ 🤖 AI Health Chatbot (RAG-Powered)

An evidence-grounded conversational health assistant that:

- Retrieves relevant chunks from verified sources (ACSM, NIH, USDA)  
- Combines them with the user's personal profile  
- Generates personalised, medically grounded responses  

Every response is traceable to a verified source, eliminating free-form AI hallucination.

---

## 2️⃣ 🏋️ AI Fitness Companion

### Injury-Aware Workout Generation
Gemini 2.5 Flash dynamically generates personalised workout plans constrained by the user's injuries, mobility limitations, fitness goals, and body stats. Contraindicated exercises are automatically excluded.

### Real-Time Form Correction
Google ML Kit Pose Detection (MediaPipe) analyses the live camera feed on-device, detects 33 body landmarks, calculates joint angles, and delivers instant coaching feedback.

### Automatic Rep Counting
A two-threshold state machine detects the up and down phases of each movement and increments the count on each completed cycle.

### Inclusive Accessibility
Supports users with:
- Wheelchairs  
- Prostheses  
- Spinal conditions  
- Joint limitations  

---

## 3️⃣ 🍱 Smart Meal & Snack Tracker

### AI Photo Logging
Take a photo of any meal and receive the top 3 dish suggestions with estimated calories and macros in under 30 seconds, powered by Gemini 2.5 Flash Lite.  
Optimised for Malaysian dishes such as:
- Nasi Lemak  
- Char Kway Teow  
- Roti Canai  

### Manual Fallback
Users can manually enter a dish name if AI recognition does not match their meal.

### Barcode Scanning
Scan packaged snack barcodes for exact nutritional data retrieved from the Open Food Facts API.

### Persistent Logging
All confirmed entries are saved to Firebase Firestore under the user's account.

---

## 4️⃣ 📊 Motivational Dashboard

- Live daily calorie tracker  
- Persistent weight goal reminder  
- Daily exercise to-do list  
- Streak tracking to sustain long-term motivation  

---

# 🛠️ Technologies Used

## 🚀 Google Technologies

| Technology | Purpose |
|------------|---------|
| **Flutter** | Cross-platform mobile UI framework — single codebase for Android and iOS |
| **Firebase Authentication** | Secure user sign-in and session management; links all user data via a single UID |
| **Firebase Cloud Firestore** | Primary NoSQL database — stores user profiles, meal logs, workout history, and RAG vector embeddings with built-in vector similarity search |
| **Firebase AI Logic** | Hosts Gemini 2.0 Flash for the health chatbot, backed by Google Cloud Vertex AI |
| **Firebase Analytics** | Tracks feature engagement, session duration, and retention post-deployment |
| **Gemini 2.5 Flash** | Generates personalised injury-aware workout plans via direct HTTP REST calls |
| **Gemini 2.5 Flash Lite** | Multimodal vision model for meal photo classification — returns top 3 dish suggestions with estimated macros |
| **Gemini 2.0 Flash** | Generates grounded, personalised health chatbot responses via Firebase AI Logic |
| **Gemini Embedding API (gemini-embedding-001)** | Converts knowledge chunks and user queries into 768-dimensional vectors for semantic similarity search in the RAG pipeline |
| **Google ML Kit Pose Detection (MediaPipe)** | On-device real-time pose estimation — detects 33 body landmarks per camera frame with no server calls required |
| **Google Cloud Vertex AI** | Enterprise AI infrastructure backing Firebase AI Logic for scalable model inference |
| **Google Cloud Run** | Serverless platform for any server-side processing beyond Firebase native capabilities |
| **Android Studio** | Primary IDE with Flutter tooling, built-in emulator, and performance profiling |
# 🏗️ System Architecture

FitSense follows a fully serverless, client-first architecture built entirely on Google technologies.  
The system is structured into three core layers:

---

## 1️⃣ Frontend — Flutter (Client Layer)

A single cross-platform **Flutter** application running on both Android and iOS.

The frontend handles all user interactions, including:

- Dashboard and progress tracking  
- Onboarding and injury input wizard  
- Real-time camera-based pose detection  
- Meal photo capture and barcode scanning  
- RAG-powered health chatbot interface  

The Flutter app communicates directly with Firebase services and external APIs through Dart service classes.  
Most operations do not require an intermediate server.

---

## 2️⃣ Backend — Fully Serverless

The backend is built entirely on managed, serverless infrastructure:

- **Firebase Authentication** for secure user identity management  
- **Firebase Cloud Firestore** for data storage  
- **Firebase AI Logic** for Gemini model inference  
- **Google Cloud Vertex AI** as the enterprise AI backbone  
- **Google Cloud Run** for any processing that exceeds Firebase's native capabilities  

There is no dedicated server to maintain.  
The infrastructure automatically scales with user demand.

---

## 3️⃣ Data Storage — Firestore (Single Source of Truth)

**Firebase Cloud Firestore** serves as the primary and only database.

It stores:

- User profiles and biometric data  
- Injury and mobility inputs  
- Meal logs and nutrition data  
- Workout history and performance metrics  
- RAG knowledge embeddings for semantic similarity search  

All data is securely scoped per user using a unique UID generated by Firebase Authentication.

---

---

# ⚙️ Installation & Setup (Windows — Android Only)

### Prerequisites
Install the following before cloning the project:

- [VS Code](https://code.visualstudio.com) with **Flutter** and **Dart** extensions (restart VS Code after installing)
- [Java JDK 17](https://adoptium.net) — choose Temurin 17 LTS, Windows x64 .msi. Check "Set JAVA_HOME" during installation
- [Android Studio](https://developer.android.com/studio) — run the setup wizard, select **Standard** install, accept all licenses, let it download the SDK
- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) — extract to `C:\dev\flutter`, then add `C:\dev\flutter\bin` to your system PATH via Environment Variables
- [Node.js LTS](https://nodejs.org) — accept all defaults

> After any PATH change on Windows, always open a **new** Command Prompt before running verification commands.

---

### 1. Create an Android Emulator
Inside Android Studio:
1. Go to **More Actions → Virtual Device Manager → Create Device**
2. Select **Pixel 7 → Next**
3. Download and select **API 34 (Android 14) → Finish**
4. Press Play to confirm it boots

---

### 2. Accept Android Licenses
```bash
flutter doctor --android-licenses
# Press y to accept each one
```

---

### 3. Verify Full Setup
```bash
flutter doctor
```
All items must show `[✓]`. Do not proceed until there are no `[✗]` errors.

> **Common fix:** If `flutter doctor` shows Android SDK Command-line Tools missing, open Android Studio → SDK Manager → SDK Tools tab → check **Android SDK Command-line Tools** → Apply.

---

### 4. Install Firebase & FlutterFire CLI
```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

Then add this to your Windows PATH:
```
C:\Users\<YourName>\AppData\Local\Pub\Cache\bin
```

Verify with:
```bash
flutterfire --version
```

---

### 5. Clone & Install Dependencies
```bash
git clone <project-url>
cd ai-fitness-companion
flutter pub get
```

---

### 6. Connect to Firebase
Inside the project folder run:
```bash
flutterfire configure
```
- Select the **ai-fitness-companion** Firebase project from the list
- Use spacebar to select **android**, then press Enter
- This auto-generates `android/app/google-services.json` and `lib/firebase_options.dart`

> If the project doesn't appear in the list, your Google account hasn't been added to Firebase yet — contact the project owner before attempting this step.

---

### 7. Configure API Keys
A `.env.example` file is included in the project root. Copy it and fill in your key:
```bash
copy .env.example .env
```
Then open `.env` and replace the placeholder with your actual Gemini API key:
```
GEMINI_API_KEY=your_actual_key_here
```
> Never commit the `.env` file. It is already listed in `.gitignore`. Contact the project owner if you need the API key value.

---

### 8. Run the App
Start your emulator first, then verify Flutter can see it:
```bash
flutter devices
```
Then launch:
```bash
flutter run --dart-define-from-file=.env
```
The first build takes a few minutes. If the app appears on the emulator you are fully set up.

---

> **Having trouble?** This guide covers the most common setup path but Windows environments vary. For detailed troubleshooting and step-by-step fixes for common errors, see [`SETUP_GUIDE.md`](./SETUP_GUIDE.md) in the repository root.

---

# 🔮 Future Roadmap

## 🚀 Short Term (0–6 Months)

- Structured user testing to validate success metrics:
  - Meal logging speed  
  - Form correction accuracy  
  - Daily engagement retention  

- Expand pose tracking beyond 3 core exercises to include:
  - Yoga  
  - Stretching  
  - Mobility routines  

- Improve Gemini meal recognition to cover more granular Malaysian dishes:
  - Distinguish roti canai, roti telur, roti sardin  
  - Improve macro estimation accuracy  

- Introduce home screen widgets for:
  - Daily goal visibility  
  - Streak reminders  

- Official launch on both Android and iOS platforms  

---

## 📈 Medium Term (6–12 Months)

- Establish university and corporate wellness partnerships for bulk user acquisition  

- Launch streak-based reward system:
  - Food vendor sponsorships  
  - Healthy lifestyle incentives  

- Expand RAG knowledge base:
  - Continuous ingestion of fitness and nutrition research  
  - Firecrawl-powered web scraping  
  - Automated embedding updates  

- Pursue government grants and public health funding to sustain free access as infrastructure scales  

---

## 🌏 Long Term (12+ Months)

- Strategic partnerships with government health bodies for national preventive health campaigns  

- Multilingual support and Southeast Asian cuisine expansion  

- Offline mode for rural and low-connectivity communities  

- Develop proprietary affordable smart hardware ecosystem:
  - Smart watch  
  - Smart ring  
  - Smart weighing scale  

  These devices will integrate directly with the FitAI app and serve as the primary revenue stream, keeping the core application permanently free and accessible.