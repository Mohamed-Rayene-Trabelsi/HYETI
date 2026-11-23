HYETI is a Flutter app for Android and iPhone. All data stays on the phone in SQLite; the only network calls are the Watch tab's lookups (AniList, TMDB, OMDb, and FotMob for football, which is unofficial and needs no key), the food search on Open Food Facts (free, no key), and the update check, which asks GitHub for the latest release.

## Flutter has changed — check before you trust memory

- Material widgets come from the `material_ui` package, not the SDK: `import 'package:material_ui/material_ui.dart';`. Do not import `package:flutter/material.dart`.
- Read the Flutter version with `flutter --version` and check https://docs.flutter.dev before using an API you are not sure still exists.

## Commands

```bash
flutter pub add <package>   # add a dependency
flutter analyze             # lint and typecheck
flutter test                # unit and widget tests
flutter run                 # run on a connected phone or emulator
flutter build apk --release --target-platform android-arm64 # installable APK in build/app/outputs/flutter-apk/
```

To publish a build, raise `version` in `pubspec.yaml` and `appVersion` in `lib/update.dart` to match (a test fails if they differ), run `tool/build-release.ps1` (analyze, test, build, check the signature, stage `release/HYETI.apk`), and attach `release/HYETI.apk` to a new GitHub release tagged `v<version>`; the README's download link points at the latest release's `HYETI.apk`. Do not commit APKs to the repository (`release/` is ignored and is only a local staging folder). Release APKs are signed with `android/hyeti-release.jks`, named with its passwords in `android/key.properties` (both kept out of git; `android/app/build.gradle.kts` reads them, or the `HYETI_KEYSTORE`, `HYETI_KEYSTORE_PASSWORD` and `HYETI_KEY_ALIAS` environment variables). It is the key that signed every release since 1.1.1 (SHA-256 `CB:A9:CC:…:C3:0E`), so only APKs signed with it install over the app on phones. Never replace it or make a new one. Without those files a release build falls back to the debug key, and `tool/build-release.ps1` refuses to stage it. On start the app compares `appVersion` with the latest release's tag and offers the download when the tag is newer, so the tag and the `HYETI.apk` file name must keep this form, and the repository must be public for the check to work.

Publishing the release starts `.github/workflows/ios.yml`, which builds an unsigned `HYETI.ipa` on a macOS runner and attaches it with `altstore.json`, the SideStore/AltStore source (its URL is `releases/latest/download/altstore.json`). iPhones are offered a release only once `HYETI.ipa` is attached (`offersUpdate` in `lib/update.dart`), and the update button hands the IPA to SideStore or AltStore. The iOS app cannot be built or run on Windows; check iOS changes by running the workflow by hand.

Run `flutter analyze` and `flutter test` before declaring any task done.

To see a screen without a phone, draw it to a PNG with real fonts and look at the file in `test/preview/`:

```bash
flutter test test/render_preview_test.dart --update-goldens
```

Do this after any layout or drawing change (the body figure in particular); add a `snap(...)` line for a new screen.

The toolchain (`flutter`, JDK 17, the Android SDK) is on the user PATH; where it is installed differs per computer.

## Layout

- `lib/main.dart` — app start, theme choice, the five-tab shell: a fixed `TopBar` (time, date, settings gear) over a swipeable `PageView`; tabs stay alive off screen.
- `lib/screens/` — one file per tab: `calendar`, `body` (gym) with `nutrition`, `wallet`, `watch`, `notes`. `settings` is a pushed page, opened from the gear in `TopBar`.
- `lib/db.dart` — the database: schema and migrations, `appDb`, the `Live` mixin, and `exportBackup` / `importBackup`.
- `lib/reminders.dart` — notifications before calendar blocks (and three days before the gym membership ends): `planReminders` works out what to show, `syncReminders` hands the next week (at most 60, an iPhone's limit) to `reminderScheduler`. `main` calls `keepRemindersInStep`, which plans again two seconds after any write. Tests swap `reminderScheduler` for a fake. `lib/reminder_settings.dart` is Settings → Reminders and the Calendar's one-time offer. Routine blocks are copied into days with `fillRoutineDays` (in `screens/calendar.dart`), for the screen and for reminders alike.
- `lib/food_search.dart` — food lookup for the Log food sheet: `basicFoods` (built-in everyday foods per 100 g, found offline), Open Food Facts search and barcode lookup (`searchProducts`, `productByBarcode`), and `readBarcode` (a photo read by ML Kit on the phone; tests swap it). Requests go through `httpClient` from `watch_api.dart`, so tests fake them the same way.
- `lib/backup.dart` — Settings → Backup: saving everything to one `.hyeti` file (an SQLite copy of the database at the current schema version) and restoring from one. An older backup is upgraded with the same migrations as an installed app; a newer one is refused.
- `lib/ui.dart` — shared widgets (`Screen`, `AppCard`, `AppButton`, `Field`, `showSheet`, …). Use these rather than raw Material widgets so screens stay consistent.
- `lib/theme.dart` — colour themes (`palettes`, `customPalette`), the colours in use (`context.colors`), spacing, calendar categories. Never hard-code a colour a theme should control; take it from `context.colors`.
- `lib/date.dart` — date helpers. Dates are `'YYYY-MM-DD'` strings; times are minutes since midnight.
- `lib/calendar_views.dart`, `lib/pickers.dart`, `lib/body_map.dart`, `lib/muscles.dart`, `lib/watch_api.dart`, `lib/countries.dart` (country → currency), `lib/receipt.dart` (receipt scan: camera, on-device text reading, picking out the total), `lib/sketch.dart` (sketch notes: strokes, painter, drawing page), `lib/football.dart` (football from FotMob: what is followed, team search, fixtures, and putting the national team's and clubs' matches on the calendar once a day), `lib/football_pickers.dart` (the football setup and the pickers Settings reuses), `lib/update.dart` (the app's version, the check for a newer GitHub release, the sheet that offers it), `lib/launch.dart` (opens the sketch editor or the jar sheet when a home-screen widget is tapped), `lib/jar.dart` (the savings jar: drawing, milestones, the "Into the jar" sheet and its "from my wallet or new money?" question), `lib/genres.dart` (one set of genre names mapped to TMDB's and AniList's, and the taste read from what is saved, which drives "For you"), `lib/genre_picker.dart` (the genre filter chip), `lib/watch_prefs.dart` (what the person watches and the genres they like: the Watch tab's first-time setup, and the pickers Settings → Watch reuses) — feature pieces.
- `android/app/src/main/kotlin/.../SketchWidget.kt` — the "Sketch" home-screen widget, in Kotlin. It reads the newest sketch from `notes` in `life.db` directly and draws it the way `SketchPainter` does, so a change to the sketch format in `lib/sketch.dart` must be repeated there. Its buttons open the app on the sketch editor through `MainActivity` and `lib/launch.dart` (a widget cannot take finger drawing itself). It cannot be previewed or tested without a phone.
- `android/app/src/main/kotlin/.../JarWidget.kt` — the "Savings jar" home-screen widget. It reads the `goal` and `currency` settings and the `saving` and `withdraw` rows of `transactions` from `life.db` and draws the jar like `JarPainter` in `lib/jar.dart`; a change to either drawing, or to how the goal or savings are stored, must be repeated there. Its button opens the app on the "Into the jar" sheet (`jar:add` in `lib/launch.dart`). Both widgets are redrawn from `MainActivity.onPause`.

## Rules

- Data access is plain SQL through `appDb` (`query`, `run`, `insert`, `transaction`). Every write notifies listeners; a screen that shows rows mixes in `Live` and reads them in `load()`.
- Wallet money: the wallet balance is income, less expenses and jar money with `from_wallet = 1`, plus money taken out of the jar (`withdraw`). Jar money with `from_wallet = 0` is new money that never was in the wallet. The jar's total is `saving` minus `withdraw`, whatever the source.
- Small preferences and single objects (theme, currency, savings goal, membership, nutrition plan, API keys) are JSON values in the `settings` table, read with `appDb.setting(key, fallback)` and written with `appDb.setSetting`.
- Schema changes: bump `_databaseVersion` in `lib/db.dart` and add an `if (from < N)` block. Never edit an existing block — installed apps and saved backups have already run it. A new table must also go in `_tables`, or backups, restores and Erase all data skip it.
- A screen's main action goes in `Screen`'s floating button (`fabLabel` / `onFab`), not in the content.
- Deleting something the user made goes through `deleteWithUndo` (or `showUndo`) so it can be taken back.
- Manga was removed in 1.5.0. Its `reading` table stays (migrations are never undone, and backups keep any rows), but nothing reads it.
- Titles on My list are left out of the Movies, Series and Anime lists (Hot, Coming soon, For you), except when searching by name; one saved while its list is on screen stays there, marked saved, until the list is left. The Football tab keeps saved matches: followed teams' matches are saved by themselves and it is their schedule.
- The Watch tab shows only the kinds chosen in `watch_prefs`. Football's on/off stays in the football settings (`off`); `saveWatchPrefs` keeps the two in step, so never store 'match' in `watch_prefs`.
- Logging a gym set ticks off today's blocks in the Gym category, and starts a rest countdown in the set sheet (`rest_seconds`, default 90, changed with its −15/+15 buttons).
- The Wallet's "Where it went" card groups this month's expenses by their label (blank labels are "Other"); the one-tap labels in the add sheet are what make it useful. There is no separate category column.
- Football errors go through `footballError` (in `screens/watch.dart`): being offline and FotMob answering in a way the app no longer understands get different messages. `followedMatches` rethrows the real error when every source fails.
- Football downloads only what the person follows or searches for (one request per team or league), never a whole day of every match. What is followed is changed in Settings → Watch, not with filters on the Football tab.
- Do not add widgets that capture horizontal drags (swipe-to-dismiss, horizontal lists): sideways swipes belong to tab switching.
- The formatter width is 120 (`analysis_options.yaml`). Run `dart format lib test` after edits.
- Android and iOS only. Do not add web or desktop platform folders.
- The home-screen widgets and `lib/launch.dart` are Android only; iOS has none. Text that names Android, widgets or the APK must check `onIOS` (from `lib/update.dart`, based on `defaultTargetPlatform` so tests can set it).
- iOS needs 15.5 or later (Google ML Kit); it is set in `ios/Podfile` and the Xcode project. A plugin that needs a new permission needs its `NS…UsageDescription` in `ios/Runner/Info.plist`, or iOS closes the app when it asks.
- The iOS app icon (`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`) and launch mark are drawn from the Android vector icon; redraw them if that icon changes.
- Widget tests use an in-memory database through `sqflite_common_ffi`; see `test/widget_test.dart` for the pattern. Database calls inside `testWidgets` must run in `tester.runAsync` (or through a tap followed by `settle`), or the test hangs until its 10-minute timeout.
- The month and week grids put a dot only for blocks that are not routine copies (`routine_id IS NULL`); the routine is the same every day and its dots said nothing.
