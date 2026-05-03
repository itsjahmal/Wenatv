# WenaTV

WenaTV is a premium Google TV and Android TV streaming interface built with Flutter.

It is designed for a cinematic TV experience with provider-based content loading, rich metadata, trailer playback, watch history, and remote-friendly navigation.

> Made with love by Steven Collins.

---

## Overview

WenaTV provides a modern streaming-app experience for Android TV and Google TV devices.

The app focuses on large-screen usability, smooth D-pad navigation, rich movie and series details, and a clean Netflix-inspired layout.

WenaTV does not host or bundle media content. Content availability depends on the providers configured by the user.

---

## Features

* Android TV / Google TV optimized UI
* Cinematic Home screen with featured hero section
* Movie and series browsing
* Provider-based content loading
* Movie and series detail screens
* Trailer playback inside the app
* Continue Watching support
* Watchlist support
* Search screen
* Settings screen
* Provider Manager
* Playback, subtitle, audio, and theme settings
* Local caching using Hive
* Network image caching
* Firebase Analytics and Crashlytics support
* Smooth media playback using `media_kit`
* YouTube trailer playback using `youtube_player_flutter`
* TV remote / D-pad navigation support
* Custom splash and startup branding

---

## Tech Stack

WenaTV is built with:

* Flutter
* Dart
* Riverpod
* GoRouter
* Hive
* Dio
* media_kit
* cached_network_image
* youtube_player_flutter
* Firebase Core
* Firebase Analytics
* Firebase Crashlytics

---

## Project Structure

```text
Wenatv/
├── android/              # Android / Android TV project files
├── assets/               # Branding, splash, animation and app assets
├── lib/
│   ├── core/             # App router, startup, theme and core utilities
│   ├── data/             # Data models, sources and repositories
│   ├── features/         # Main app features
│   │   ├── details/      # Movie and series detail screens
│   │   ├── home/         # Home screen and content rails
│   │   ├── player/       # Video player experience
│   │   ├── providers/    # Provider management and loading
│   │   ├── search/       # Search experience
│   │   ├── settings/     # App settings
│   │   └── splash/       # Startup and splash flow
│   ├── shared/           # Shared widgets
│   ├── theme/            # App styling
│   ├── widgets/          # Reusable UI widgets
│   └── main.dart         # App entry point
├── test/                 # Flutter tests
├── pubspec.yaml          # Flutter dependencies and assets
└── README.md
```

---

## Requirements

Before running the app, make sure you have:

* Flutter SDK installed
* Dart SDK installed
* Android Studio or VS Code
* Android SDK installed
* Android TV / Google TV emulator or physical TV device
* Firebase project configuration if using analytics/crash reporting

Recommended target:

* Android TV
* Google TV
* Landscape mode
* 16:9 displays
* Remote / D-pad input

---

## Getting Started

Clone the repository:

```bash
git clone https://github.com/itsjahmal/Wenatv.git
cd Wenatv
```

Install Flutter dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

To run on a specific Android TV emulator or device:

```bash
flutter devices
flutter run -d <device-id>
```

---

## Building for Android

Build a debug APK:

```bash
flutter build apk --debug
```

Build a release APK:

```bash
flutter build apk --release
```

Build an Android App Bundle:

```bash
flutter build appbundle --release
```

---

## Firebase Setup

WenaTV includes Firebase support for analytics and crash reporting.

If Firebase is enabled, make sure your Android Firebase config file is added correctly:

```text
android/app/google-services.json
```

If Firebase is not configured, the app should still handle startup safely, but analytics and crash reporting may not be active.

---

## Local Storage

WenaTV uses Hive for local storage and caching.

Hive may be used for:

* Continue Watching data
* User preferences
* Home screen cache
* Provider settings
* Watchlist data

---

## Provider System

WenaTV is designed to work with user-managed providers.

Providers may be used to load:

* Movies
* Series
* Episodes
* Stream sources
* Metadata references

WenaTV does not host, upload, or distribute provider content.

---

## Media Playback

The app uses `media_kit` for video playback.

Playback features may include:

* Movie playback
* Episode playback
* Resume playback
* Continue Watching
* Playback progress tracking
* Stream source selection

---

## Trailer Playback

WenaTV supports in-app trailer playback using `youtube_player_flutter`.

Trailer behavior:

* Trailers open inside the app
* Trailers should not launch an external browser
* If multiple trailers are available, official trailers should be prioritized
* If no trailer exists, the app should show a friendly message

---

## TV Navigation

WenaTV is designed for Android TV / Google TV remote navigation.

Navigation should support:

* D-pad up, down, left, and right
* Focus highlights
* Back button navigation
* Sidebar navigation
* Player controls
* Settings navigation
* Detail screen actions

Back behavior should return to the previous screen and only exit the app when already on the Home screen.

---

## App Branding

The app includes WenaTV branding assets such as:

* Startup logo
* Splash assets
* Boot animation assets
* Dark cinematic visual style
* Red accent focus color

---

## Disclaimer

WenaTV does not host, upload, store, or distribute any media content.

Content availability depends on user-configured providers. Users are responsible for ensuring that any provider, source, or stream they add complies with applicable laws and content rights in their region.

This project is intended as a streaming interface and media browsing experience.

---

## Developer

Made with love by Steven Collins.

---

## Support the Developer

Enjoying WenaTV? You can support future improvements by buying the developer a coffee.

PayPal:

```text
radiomagik62@gmail.com
```

---

## Security Notes

Do not commit private keys, API tokens, signing files, Firebase secrets, or production credentials to the repository.

Recommended:

* Keep API keys in secure environment files
* Keep signing keys outside public repositories
* Rotate any exposed credentials
* Use `.gitignore` for sensitive files
* Use different keys for development and production

---

## Useful Commands

Clean project:

```bash
flutter clean
flutter pub get
```

Run analyzer:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Build release APK:

```bash
flutter build apk --release
```

---

## License

This project is free to use under the MIT License.

You are allowed to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of this software, as long as the original license and copyright notice are included.

See the `LICENSE` file for full license details.
