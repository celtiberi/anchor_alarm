# Firebase Setup Guide

This document explains how to configure Firebase for the Anchor Alarm app.

## Prerequisites

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Enable the following Firebase services:
   - **Cloud Firestore** - For storing sessions, positions, and alarms
   - **Firebase Authentication** - For user authentication (if needed)
   - **Firebase Cloud Messaging** - For push notifications

## Android Configuration

### Step 1: Download `google-services.json`

1. Go to Firebase Console → Project Settings
2. Under "Your apps", click on the Android app (or add one if it doesn't exist)
3. Download the `google-services.json` file
4. Place it in: `android/app/google-services.json`

**Important**: The package name in Firebase must match your app's package name:
- Current package name: `com.sailorsparrot.anchoralarm`
- Update this in Firebase Console if needed, or update your app's package name

### Step 2: Verify Android Build Configuration

The following should already be configured:
- ✅ Google Services plugin added to `android/build.gradle.kts`
- ✅ Google Services plugin applied in `android/app/build.gradle.kts`

## iOS Configuration

### Step 1: Download `GoogleService-Info.plist`

1. Go to Firebase Console → Project Settings
2. Under "Your apps", click on the iOS app (or add one if it doesn't exist)
3. Download the `GoogleService-Info.plist` file
4. Place it in: `ios/Runner/GoogleService-Info.plist`

**Important**: The bundle identifier in Firebase must match your app's bundle identifier:
- Current bundle identifier: `com.sailorsparrot.anchoralarm`
- Update this in Firebase Console if needed, or update your app's bundle identifier

### Step 2: Add to Xcode Project

1. Open `ios/Runner.xcworkspace` in Xcode
2. Right-click on the `Runner` folder in the project navigator
3. Select "Add Files to Runner..."
4. Select `GoogleService-Info.plist`
5. Make sure "Copy items if needed" is checked
6. Ensure the file is added to the Runner target

## Verification

After adding the configuration files:

1. Run `flutter pub get` to ensure all dependencies are installed
2. For iOS: Run `cd ios && pod install && cd ..`
3. Run the app and check logs for "Firebase initialized successfully"

## Troubleshooting

### Android: "File google-services.json is missing"
- Ensure `google-services.json` is in `android/app/` directory
- Verify the file name is exactly `google-services.json` (case-sensitive)

### iOS: "GoogleService-Info.plist not found"
- Ensure `GoogleService-Info.plist` is in `ios/Runner/` directory
- Verify it's added to the Xcode project and included in the Runner target
- Try running `pod install` again

### Firebase initialization fails
- Check that the package name (Android) or bundle identifier (iOS) matches Firebase Console
- Verify the configuration files are valid JSON/XML
- Check that Firebase services are enabled in Firebase Console

## Firestore Security Rules

⚠️ **Required**: You must configure Firestore security rules for the app to work.

1. Go to Firebase Console → Firestore Database → Rules
2. See `FIRESTORE_RULES.md` for the complete security rules configuration
3. Copy and paste the rules into the Firebase Console
4. Click **Publish**

**Quick Start Rules** (for development):
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

These rules allow any authenticated user to read/write. For production, use the more restrictive rules in `FIRESTORE_RULES.md`.

## Enable Anonymous Authentication

The app uses Firebase Anonymous Authentication:

1. Go to Firebase Console → Authentication
2. Click **Get Started** (if not already enabled)
3. Go to **Sign-in method** tab
4. Enable **Anonymous** authentication
5. Click **Save**

## Security Notes

⚠️ **Important**: The `google-services.json` and `GoogleService-Info.plist` files contain sensitive configuration data. 

- Do NOT commit these files to public repositories
- Add them to `.gitignore` if they contain production credentials
- Consider using different Firebase projects for development and production

