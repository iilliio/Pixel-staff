# Open Pixel Poi — Run Locally in your IDE

This folder contains the Flutter app. Below are step‑by‑step instructions to run it locally on macOS, Windows, Linux, Android, iOS, and Web using Android Studio or VS Code.

## Prerequisites

- Install Flutter (stable channel) and add it to your PATH. See the official guide: [Install Flutter](https://docs.flutter.dev/get-started/install).
- Install an IDE:
  - Android Studio (recommended for Android emulators and tooling), or
  - VS Code with the Flutter and Dart extensions.
- Run `flutter doctor` and address any reported issues.

```bash
flutter doctor
```

## Project Setup (all OS)

1) Open the `open_pixel_poi` folder in your IDE.
2) Fetch dependencies:

```bash
flutter pub get
```

3) Select a target device in your IDE, or list devices via CLI:

```bash
flutter devices
```

4) Run the app:

```bash
flutter run
```

The app uses the microphone for audio‑reactive visuals. When prompted by the OS or browser, allow microphone access.

## Run on Android

Requirements:
- Android Studio with Android SDK, an emulator or a physical device with USB debugging enabled.

Steps:
1) Start an Android emulator from Android Studio (AVD Manager) or connect a device.
2) Ensure the device shows up: `flutter devices`.
3) Run from the IDE (Run ▶) or via CLI: `flutter run -d <deviceId>`.
4) Accept the microphone permission prompt on first launch.

## Run on iOS (macOS only)

Requirements:
- macOS with Xcode installed (and Command Line Tools), CocoaPods (`sudo gem install cocoapods`).

Steps:
1) Start an iOS Simulator from Xcode, or connect a real device (requires code signing).
2) From this folder:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter run -d <ios-device-id>
```

Notes:
- On a real device you must set a valid signing team in `Runner.xcodeproj` (Xcode).
- Accept the microphone permission.

## Run on macOS Desktop (macOS only)

Requirements:
- Xcode installed.

Steps:
```bash
flutter config --enable-macos-desktop
flutter run -d macos
```

If the mic meter doesn’t move, allow the app under System Settings → Privacy & Security → Microphone.

## Run on Windows Desktop (Windows only)

Requirements:
- Windows 10/11, Flutter desktop support enabled, Visual Studio 2022 with “Desktop development with C++” workload.

Steps:
```powershell
flutter config --enable-windows-desktop
flutter run -d windows
```

Allow microphone access in Windows Privacy settings if prompted.

## Run on Linux Desktop (example: Ubuntu/Debian)

Requirements:
- Flutter desktop support enabled and GTK/build tools installed.

Install dependencies (Ubuntu/Debian example):
```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

Steps:
```bash
flutter config --enable-linux-desktop
flutter run -d linux
```

Grant microphone permission if your distro prompts for it.

## Run on Web (Chrome)

Steps:
```bash
flutter config --enable-web
flutter run -d chrome
```

When the browser asks for microphone access, click Allow. Localhost is considered a secure origin and should allow mic access.

## Running from IDEs

### Android Studio
- File → Open… → choose the `open_pixel_poi` folder.
- Use the device selector to pick an emulator or device.
- Click Run ▶ to launch.

### VS Code
- Open the `open_pixel_poi` folder.
- Ensure Flutter and Dart extensions are installed.
- Use the device picker in the status bar to select a target.
- Press F5 (Run and Debug) or run `Flutter: Run`.

## Troubleshooting

- `flutter doctor` shows issues: follow the suggestions to install missing toolchains/SDKs.
- iOS CocoaPods errors: run `cd ios && pod repo update && pod install`.
- iOS real device build fails: open `ios/Runner.xcworkspace` in Xcode and set a valid signing team.
- Microphone not working:
  - Ensure you accepted the permission prompt.
  - macOS: System Settings → Privacy & Security → Microphone → enable for the app (Runner).
  - Windows: Settings → Privacy & security → Microphone → allow apps to access your microphone.
  - Browser: Check site permissions (lock icon) and ensure mic is allowed for `localhost`.

## Notes

- The project was originally designed for Android, but Flutter desktop/web platforms are present. Behavior may vary slightly across platforms depending on audio backends.
- If you run into platform‑specific plugin issues, consult the plugin docs used by the app (e.g., `record`) and Flutter’s platform setup guides.
