import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'theme.dart';
import 'ui.dart';
import 'watch_api.dart' show httpClient;

/// The version of this build. Must match `version` in pubspec.yaml; a test checks that it does.
const appVersion = '1.4.0';

/// The GitHub repository whose releases carry `HYETI.apk`.
const _repo = 'Mohamed-Rayene-Trabelsi/HYETI';

const _timeout = Duration(seconds: 15);

/// A published build of the app.
class Release {
  const Release({required this.version, required this.notes, required this.url});

  /// Without the leading "v", e.g. "1.0.5".
  final String version;

  /// What the release says about itself; may be empty.
  final String notes;

  /// Where `HYETI.apk` downloads from.
  final String url;
}

/// The numbers of a version, e.g. "v1.0.5+6" → [1, 0, 5].
List<int> _parts(String version) {
  final core = version.trim().replaceFirst(RegExp('^[vV]'), '').split(RegExp('[+-]')).first;
  return [for (final part in core.split('.')) int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0];
}

/// Whether version [candidate] comes after version [current].
bool isNewer(String candidate, String current) {
  final a = _parts(candidate), b = _parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Reads GitHub's answer for a release.
Release parseRelease(Map<String, dynamic> json) {
  final assets = (json['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
  final apk = assets.where((a) => a['name'] == 'HYETI.apk').firstOrNull?['browser_download_url'] as String?;
  return Release(
    version: (json['tag_name'] as String).replaceFirst(RegExp('^[vV]'), ''),
    notes: (json['body'] as String? ?? '').trim(),
    url: apk ?? 'https://github.com/$_repo/releases/latest/download/HYETI.apk',
  );
}

/// The newest release on GitHub. Throws when offline or when GitHub does not answer with one.
Future<Release> fetchLatestRelease() async {
  final res = await httpClient
      .get(
        Uri.https('api.github.com', '/repos/$_repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      )
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('GitHub answered ${res.statusCode}');
  return parseRelease(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
}

/// On app start: offers a newer release if there is one the user has not skipped.
/// Says nothing when offline or up to date.
Future<void> promptForUpdate(BuildContext context) async {
  final Release release;
  try {
    release = await fetchLatestRelease();
  } catch (_) {
    return;
  }
  if (!isNewer(release.version, appVersion)) return;
  if (appDb.setting('skipped_version', '') == release.version) return;
  if (context.mounted) showUpdateSheet(context, release);
}

/// The sheet that offers [release].
Future<void> showUpdateSheet(BuildContext context, Release release) {
  return showSheet(
    context,
    title: 'Update available',
    builder: (sheet) => FormColumn(
      children: [
        T('Version ${release.version} is out. This phone has $appVersion.'),
        if (release.notes.isNotEmpty) T(release.notes, dim: true, maxLines: 12),
        AppButton(
          'Download update',
          icon: Icons.download,
          onPressed: () async {
            Navigator.pop(sheet);
            try {
              await launchUrl(Uri.parse(release.url), mode: LaunchMode.externalApplication);
            } catch (_) {
              // No browser to hand the link to; nothing useful to do about it here.
            }
          },
        ),
        const T(
          'Your browser downloads HYETI.apk. Open the file when it finishes to install it; your data stays.',
          variant: TextVariant.small,
          dim: true,
        ),
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: AppButton('Later', kind: ButtonKind.soft, onPressed: () => Navigator.pop(sheet)),
            ),
            Expanded(
              child: AppButton(
                'Skip this version',
                kind: ButtonKind.soft,
                onPressed: () {
                  Navigator.pop(sheet);
                  appDb.setSetting('skipped_version', release.version);
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
