HYETI is a Flutter app for Android only. All data stays on the phone in SQLite; the only network calls are the Watch tab's lookups (AniList, TMDB, OMDb, and FotMob for football, which is unofficial and needs no key), the reading list's import from a link the person pastes, and the update check, which asks GitHub for the latest release.

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

To publish a build, raise `version` in `pubspec.yaml` and `appVersion` in `lib/update.dart` to match (a test fails if they differ), build, and attach `app-release.apk`, renamed `HYETI.apk`, to a new GitHub release tagged `v<version>`; the README's download link points at the latest release's `HYETI.apk`. Do not commit APKs to the repository (`release/` is ignored and is only a local staging folder). The APK is signed with the debug key of the computer that built it, so only builds from that computer install over the app already on the phone. On start the app compares `appVersion` with the latest release's tag and offers the download when the tag is newer, so the tag and the `HYETI.apk` file name must keep this form, and the repository must be public for the check to work.

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
- `lib/db.dart` — the database: schema and migrations, `appDb`, and the `Live` mixin.
- `lib/ui.dart` — shared widgets (`Screen`, `AppCard`, `AppButton`, `Field`, `showSheet`, …). Use these rather than raw Material widgets so screens stay consistent.
- `lib/theme.dart` — colour themes (`palettes`, `customPalette`), the colours in use (`context.colors`), spacing, calendar categories. Never hard-code a colour a theme should control; take it from `context.colors`.
- `lib/date.dart` — date helpers. Dates are `'YYYY-MM-DD'` strings; times are minutes since midnight.
- `lib/calendar_views.dart`, `lib/pickers.dart`, `lib/body_map.dart`, `lib/muscles.dart`, `lib/watch_api.dart`, `lib/countries.dart` (country → currency), `lib/receipt.dart` (receipt scan: camera, on-device text reading, picking out the total), `lib/sketch.dart` (sketch notes: strokes, painter, drawing page), `lib/football.dart` (football from FotMob: what is followed, team search, fixtures, and putting the national team's and clubs' matches on the calendar once a day), `lib/football_pickers.dart` (the football setup and the pickers Settings reuses), `lib/update.dart` (the app's version, the check for a newer GitHub release, the sheet that offers it), `lib/launch.dart` (opens the sketch editor or the jar sheet when a home-screen widget is tapped), `lib/jar.dart` (the savings jar: drawing, milestones, the "Into the jar" sheet and its "from my wallet or new money?" question), `lib/genres.dart` (one set of genre names mapped to TMDB's and AniList's, and the taste read from what is saved, which drives "For you"), `lib/genre_picker.dart` (the genre filter chip), `lib/watch_prefs.dart` (what the person watches and the genres they like: the Watch tab's first-time setup, and the pickers Settings → Watch reuses), `lib/reading.dart` (the reading list's CSV reading and writing, merging an import, importing from a link) — feature pieces. `lib/screens/reading.dart` is the Manga part of the Watch tab.
- `android/app/src/main/kotlin/.../SketchWidget.kt` — the "Sketch" home-screen widget, in Kotlin. It reads the newest sketch from `notes` in `life.db` directly and draws it the way `SketchPainter` does, so a change to the sketch format in `lib/sketch.dart` must be repeated there. Its buttons open the app on the sketch editor through `MainActivity` and `lib/launch.dart` (a widget cannot take finger drawing itself). It cannot be previewed or tested without a phone.
- `android/app/src/main/kotlin/.../JarWidget.kt` — the "Savings jar" home-screen widget. It reads the `goal` and `currency` settings and the `saving` and `withdraw` rows of `transactions` from `life.db` and draws the jar like `JarPainter` in `lib/jar.dart`; a change to either drawing, or to how the goal or savings are stored, must be repeated there. Its button opens the app on the "Into the jar" sheet (`jar:add` in `lib/launch.dart`). Both widgets are redrawn from `MainActivity.onPause`.

## Rules

- Data access is plain SQL through `appDb` (`query`, `run`, `insert`, `transaction`). Every write notifies listeners; a screen that shows rows mixes in `Live` and reads them in `load()`.
- Wallet money: the wallet balance is income, less expenses and jar money with `from_wallet = 1`, plus money taken out of the jar (`withdraw`). Jar money with `from_wallet = 0` is new money that never was in the wallet. The jar's total is `saving` minus `withdraw`, whatever the source.
- Small preferences and single objects (theme, currency, savings goal, membership, nutrition plan, API keys) are JSON values in the `settings` table, read with `appDb.setting(key, fallback)` and written with `appDb.setSetting`.
- Schema changes: bump `_databaseVersion` in `lib/db.dart` and add an `if (from < N)` block. Never edit an existing block — installed apps have already run it.
- A screen's main action goes in `Screen`'s floating button (`fabLabel` / `onFab`), not in the content.
- Deleting something the user made goes through `deleteWithUndo` (or `showUndo`) so it can be taken back.
- The Watch tab shows only the kinds chosen in `watch_prefs`. Football's on/off stays in the football settings (`off`); `saveWatchPrefs` keeps the two in step, so never store 'match' in `watch_prefs`.
- Football downloads only what the person follows or searches for (one request per team or league), never a whole day of every match. What is followed is changed in Settings → Watch, not with filters on the Football tab.
- Do not add widgets that capture horizontal drags (swipe-to-dismiss, horizontal lists): sideways swipes belong to tab switching.
- The formatter width is 120 (`analysis_options.yaml`). Run `dart format lib test` after edits.
- Android only. Do not add iOS, web or desktop platform folders.
- Widget tests use an in-memory database through `sqflite_common_ffi`; see `test/widget_test.dart` for the pattern.
