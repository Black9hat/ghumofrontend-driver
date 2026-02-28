# Google Play Store Signing & Deployment Guide

This guide explains how to properly sign your Flutter app for Google Play Store release.

## Prerequisites

- [Java Development Kit (JDK) 11+](https://www.oracle.com/java/technologies/javase-jdk11-downloads.html)
- [Android SDK](https://developer.android.com/studio)
- Flutter SDK properly installed
- Google Play Developer Account

## Step 1: Create a Release Keystore

### Windows (PowerShell)
```powershell
$JAVA_HOME = "C:\Program Files\Android\jdk\microsoft_dist_openjdk_11.0.11_9"
& "$JAVA_HOME\bin\keytool.exe" -genkey -v -keystore "android/app/key.jks" -keyalg RSA -keysize 2048 -validity 10950 -alias ghumo_key
```

### macOS/Linux
```bash
keytool -genkey -v -keystore android/app/key.jks -keyalg RSA -keysize 2048 -validity 10950 -alias ghumo_key
```

**When prompted, enter:**
- Keystore password: (save this securely)
- Key alias password: (save this securely)
- Common Name (CN): Your Name or Company
- Organizational Unit (OU): Development
- Organization (O): Your Company
- City (L): Your City
- State (ST): Your State
- Country (C): Your Country Code (e.g., US)

## Step 2: Set Environment Variables

This app is configured to read signing keys from environment variables. You have two options:

### Option A: Set Environment Variables (Recommended)

#### Windows (PowerShell)
```powershell
# Set these environment variables (persistent in your system)
[Environment]::SetEnvironmentVariable("KEYSTORE_PATH", "C:\full\path\to\android\app\key.jks", [EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("KEYSTORE_PASSWORD", "your_keystore_password", [EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("KEY_ALIAS", "ghumo_key", [EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("KEY_PASSWORD", "your_key_password", [EnvironmentVariableTarget]::User)

# Verify
Get-ChildItem Env:KEYSTORE*
Get-ChildItem Env:KEY*
```

#### macOS/Linux
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.bash_profile
export KEYSTORE_PATH="$HOME/path/to/android/app/key.jks"
export KEYSTORE_PASSWORD="your_keystore_password"
export KEY_ALIAS="ghumo_key"
export KEY_PASSWORD="your_key_password"

# Then reload:
source ~/.zshrc  # or ~/.bashrc
```

### Option B: Direct Environment (One-Time)

```bash
# Windows (PowerShell)
$env:KEYSTORE_PATH = "C:\full\path\to\android\app\key.jks"
$env:KEYSTORE_PASSWORD = "your_keystore_password"
$env:KEY_ALIAS = "ghumo_key"
$env:KEY_PASSWORD = "your_key_password"

# Then run the build command
```

## Step 3: Build Release APK

```bash
cd path/to/drivergo

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build release APK (for testing on devices)
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Step 4: Build Release App Bundle (Required for Play Store)

```bash
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

## Step 5: Upload to Google Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app (Ghumo Partner)
3. Navigate to **Release** → **Production**
4. Click **Create new release**
5. Upload the `.aab` file from `build/app/outputs/bundle/release/app-release.aab`
6. Complete the release form:
   - What's new in this release: Describe changes
   - Review release details
   - Submit for review

## Important Security Notes

⚠️ **Never commit `key.jks` to version control!**

1. Add to `.gitignore`:
```
android/app/key.jks
android/app/*.jks
```

2. Store the keystore file securely (encrypted backup)

3. **Never share your passwords** - These are production signing credentials

4. Keep separate keystores for different apps

5. The `10950-day validity` equals ~30 years, so you won't need to regenerate it often

## Troubleshooting

### "KEYSTORE_PATH not found"
- Ensure the path in environment variable is absolute
- Restart terminal/IDE after setting environment variables
- On Windows, use double backslashes: `C:\\path\\to\\key.jks`

### "Invalid keystore"
- Verify keystore file exists and is readable
- Confirm passwords are correct
- Try regenerating the keystore

### "Unable to find Java"
- Install JDK 11 or higher
- Set `JAVA_HOME` environment variable pointing to JDK installation

## Version Management

Update version before each release in `pubspec.yaml`:
```yaml
version: 1.0.0+1  # Format: major.minor.patch+buildNumber
```

**Important:** Each Play Store release must have a higher `buildNumber` than the previous one.

## Play Store Requirements Checklist

Before submitting:

- [ ] App icon properly configured (see assets/images/)
- [ ] App name: "Ghumo Partner"
- [ ] Package name: `com.ghumo.driver`
- [ ] Min SDK: 23
- [ ] Target SDK: 35 (Latest)
- [ ] Privacy Policy URL configured in Play Console
- [ ] App description updated in pubspec.yaml
- [ ] Screenshots and store listing completed
- [ ] Content rating questionnaire submitted
- [ ] Target audience set appropriately
- [ ] All permissions justified in app

## Release Checklist

- [ ] Code is tested and stable
- [ ] No debug output in release (wrapped in kDebugMode)
- [ ] Sensitive API keys are not hardcoded
- [ ] Version number incremented
- [ ] Build locally and test APK
- [ ] Keystore password is secure
- [ ] Upload to Play Console
- [ ] Submit for review

---

**Last Updated:** February 2026
**Package:** com.ghumo.driver
**App Name:** Ghumo Partner
