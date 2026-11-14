# HYETI

A personal planner for Android, built with Flutter. Everything is stored on the phone.

| Tab | What it does |
| --- | --- |
| Calendar | Weekly routine blocks copied into each day; day, week and month views; running-late shifts and days off |
| Body | Gym: muscle map, exercise suggestions, set logging, membership countdown. Nutrition: calorie and macro plan, food log |
| Wallet | Income, spending and savings, weekly budget, savings goal |
| Watch | Watchlist with hot and upcoming movies, series and anime; adds watch nights to the calendar |
| Notes | Searchable notes with pinning |
| Settings | Theme, week start, units, currency, API keys, erase all data |

## Install it on a phone

The latest build is kept in this repository at [`release/HYETI.apk`](release/HYETI.apk).

1. On the phone, sign in to GitHub in the browser (the repository is private) and open
   <https://github.com/Mohamed-Rayene-Trabelsi/HYETI/raw/main/release/HYETI.apk>.
2. Open the downloaded file and allow the browser to install apps when Android asks.

Installing a newer build over an older one keeps your data. The file is for 64-bit ARM phones, which covers nearly every Android phone sold since 2017.

## Run it

1. Plug in an Android phone with USB debugging on (or start an emulator).
2. In VS Code, open this folder and press `F5`, or run:

   ```bash
   flutter run
   ```

## Build an APK

Raise `version` in `pubspec.yaml` first (for example `1.0.1+2`), then build and copy the result into `release/`:

```bash
flutter build apk --release --target-platform android-arm64
```

```bash
cp build/app/outputs/flutter-apk/app-release.apk release/HYETI.apk
```

Commit and push `release/HYETI.apk` to publish it.

The APK is signed with the debug key of the computer that built it. A build from a different computer has a different signature, and Android will refuse to install it over the old app until the old app is uninstalled, which erases its data. Keep building on the same computer, or set up a release key before switching.

## Check the code

```bash
flutter analyze
```

```bash
flutter test
```

## Watch tab keys

Anime needs no key. Movies and series need a free TMDB key, and IMDb ratings a free OMDb key; paste both in under Settings.

## Folders

| Path | What is in it |
| --- | --- |
| `lib/` | The app. `main.dart` starts it; `screens/` has one file per tab; the other files are shared pieces (database, theme, widgets, dates) |
| `test/` | Unit and widget tests; `test/preview/` holds pictures of the screens drawn by `render_preview_test.dart` |
| `android/` | The Android project Flutter builds |
| `release/` | The installable APK |

`AGENTS.md` has the working rules for the code.
