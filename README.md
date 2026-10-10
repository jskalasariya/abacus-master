# Abacus Master

**A child-friendly arithmetic practice app built with Flutter.**

Abacus Master helps children improve their calculation speed, accuracy,
and confidence through configurable arithmetic practice, multiple-choice
questions, timed tests, and progress tracking.

The app is designed for Android first, with an offline-first
architecture and local profile management.

## Features

### Practice and assessments

-   Beginner, Medium, and Advanced difficulty levels.
-   Addition, subtraction, multiplication, division, and mixed
    arithmetic.
-   Configurable decimal precision, including whole-number practice.
-   Four multiple-choice answers per question, with one correct answer.
-   Randomized questions and answer choices.
-   Configurable question count and test duration.
-   Default test configuration: 100 questions and 10 minutes.
-   Immediate answer feedback or feedback at the end of the test.
-   Pause, resume, and cancel support where available in the practice
    flow.

### Profiles and security

-   Create and manage individual local profiles.
-   Password-based profile login.
-   Change a profile password after verifying the current password.
-   Passwords are hashed using Argon2id with a fresh random salt.
-   Profile-specific settings and practice history.

### Results and progress

-   Review completed practice sessions.
-   View submitted answers and correct answers.
-   Track accuracy, response times, and performance trends.
-   View practice history and statistics for the signed-in profile.

### Offline-first architecture

-   Local SQLite persistence.
-   No backend or cloud account required for the current version.
-   Profile settings, practice sessions, and history are stored locally
    on the device.

## Technology stack

-   **Language:** Dart
-   **Framework:** Flutter
-   **UI:** Material 3
-   **Database:** SQLite using Drift's database APIs
-   **Password hashing:** Argon2id
-   **Testing:** Flutter unit and widget tests

## Requirements

Install the following tools before developing the project:

-   Flutter SDK
-   Dart SDK compatible with the project's Flutter version
-   Android SDK and Android command-line tools
-   Java Development Kit compatible with the Android Gradle
    configuration
-   Git

Verify your Flutter environment:

``` powershell
flutter doctor -v
```

## Getting started

Clone the repository:

``` powershell
git clone git@github.com:jskalasariya/abacus-master.git
cd abacus-master
```

Install dependencies:

``` powershell
flutter pub get
```

Check code quality:

``` powershell
flutter analyze
```

Run automated tests:

``` powershell
flutter test --reporter expanded
```

Run the app on a connected device or available development target:

``` powershell
flutter devices
flutter run
```

For Android development, configure the Android SDK and connect an
Android device or start an emulator.

## Build the Android APK

Build a release APK:

``` powershell
flutter build apk --release
```

The generated APK is available at:

``` text
build/app/outputs/flutter-apk/app-release.apk
```

Install it on a connected Android device using ADB:

``` powershell
adb install -r "build/app/outputs/flutter-apk/app-release.apk"
```

You can also transfer the APK to an Android phone and install it
manually. Android may ask you to allow installation from the application
used to open the APK.

## Project structure

``` text
lib/
  application/    # Application services and controllers
  data/           # SQLite persistence and repositories
  domain/         # Arithmetic, profiles, and practice models
  presentation/   # Screens and UI components

test/             # Automated tests

android/          # Android application configuration
ios/              # iOS project configuration
web/              # Web project configuration
windows/          # Windows project configuration
linux/            # Linux project configuration
macos/            # macOS project configuration
```

The exact contents may evolve as the project grows.

## Current status

The project has an implemented practice flow, local profile
authentication, persisted settings, password changes, practice history,
and statistics.

The latest reported automated test run passed **114 tests**, and
`flutter analyze` reported no issues. A release APK was also
successfully built at 55.2 MB during development.

These results reflect the development state at the time of that run;
repeat the checks against the latest code before releasing a new build.

## Security and data considerations

-   Profiles and their data are stored locally.
-   Passwords are hashed rather than stored as plaintext.
-   The current application does not provide cloud synchronization or
    password recovery.
-   Local database encryption and a complete production security review
    have not been established.
-   Protect access to devices containing children's profile data.

## Roadmap

Potential future improvements include:

-   Additional accessibility and tablet-layout testing.
-   Further improvements to practice insights and learning progression.
-   Optional sound and theme preferences.
-   iOS support and additional platform validation.

## Contributing

Contributions, bug reports, and suggestions are welcome. Please describe
the problem, the expected behavior, and the steps to reproduce it when
reporting a bug.

## License

No license has been specified yet. Until a license is added to the
repository, permission to reuse, modify, or redistribute this project
should not be assumed.

------------------------------------------------------------------------

**Abacus Master** --- Practice a little. Improve every day.
