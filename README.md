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

## Run it

1. Plug in an Android phone with USB debugging on (or start an emulator).
2. In VS Code, open this folder and press `F5`, or run:

   ```bash
   flutter run
   ```

## Build an APK

```bash
flutter build apk --release
```

The file is written to `build/app/outputs/flutter-apk/app-release.apk`. Copy it to a phone and open it to install.

## Check the code

```bash
flutter analyze
```

```bash
flutter test
```

## Watch tab keys

Anime needs no key. Movies and series need a free TMDB key, and IMDb ratings a free OMDb key; paste both in under Settings.

The previous Expo/React Native version of this app is kept on the `expo-archive` branch.
