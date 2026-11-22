import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'db.dart';
import 'jar.dart';
import 'screens/wallet.dart';
import 'sketch.dart';

/// The app's navigator, so a home-screen widget can open a page whatever is on screen.
final navigatorKey = GlobalKey<NavigatorState>();

const _channel = MethodChannel('hyeti/launch');

/// Listens for the home-screen widgets' buttons (see SketchWidget.kt and JarWidget.kt) and opens what they ask for: once for the tap
/// that started the app, and again for every tap while it runs.
Future<void> listenForWidgetTaps() async {
  // The widgets exist only on Android.
  if (defaultTargetPlatform != TargetPlatform.android) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'open') await openFromWidget(call.arguments as String?);
  });
  try {
    await openFromWidget(await _channel.invokeMethod<String>('take'));
  } on MissingPluginException {
    // Tests and previews have no Android side.
  }
}

/// `jar:add` opens the "Into the jar" sheet; `sketch:new` opens a blank canvas; `sketch:<id>` reopens that sketch note, or a blank one if it is gone.
Future<void> openFromWidget(String? request) async {
  if (request == 'jar:add') {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final currency = appDb.setting('currency', r'$');
    await openJarDrop(context, money: (n) => formatMoney(n, currency));
    return;
  }
  if (request == null || !request.startsWith('sketch:')) return;
  final id = int.tryParse(request.substring('sketch:'.length));
  Rec? note;
  if (id != null) {
    final rows = await appDb.query('SELECT * FROM notes WHERE id = ? AND sketch IS NOT NULL', [id]);
    note = rows.firstOrNull;
  }
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;
  navigator.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => SketchEditor(note: note)));
}
