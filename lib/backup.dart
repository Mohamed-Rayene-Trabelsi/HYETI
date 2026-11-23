import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'date.dart';
import 'db.dart';
import 'theme.dart';
import 'ui.dart';

/// Asks where to save [bytes] as [name]. True when it was saved. Replaceable in tests, which have no file dialogs.
Future<bool> Function(String name, Uint8List bytes) saveBackupFile = (name, bytes) async {
  final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/octet-stream');
  return uri != null;
};

/// Asks for a backup file and returns its bytes; null when the person backs out. Replaceable in tests.
Future<Uint8List?> Function() pickBackupFile = () async {
  final file = await FilePicker.pickFile(type: FileType.any);
  return file == null ? null : await file.readAsBytes();
};

/// Days since the last backup was saved; null when there never was one.
int? daysSinceBackup() {
  final last = appDb.setting<String?>('last_backup', null);
  return last == null || !isDateKey(last) ? null : daysBetween(last, todayKey());
}

/// "Last saved today", "Last saved 12 days ago", "Never saved": for the Settings row.
String backupSummary() => switch (daysSinceBackup()) {
  null => 'Never saved',
  0 => 'Last saved today',
  1 => 'Last saved yesterday',
  final n => 'Last saved $n days ago',
};

/// Whether it is time to save another backup: never saved, or not for a month.
bool backupDue() => (daysSinceBackup() ?? 999) >= 30;

/// Saving everything to one file, and putting it back from one.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  bool _confirmRestore = false;

  /// What the last action did, and whether it went wrong.
  String _note = '';
  bool _failed = false;

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = '';
    });
    String? note;
    var failed = false;
    try {
      note = await action();
    } on BackupError catch (e) {
      note = e.message;
      failed = true;
    } catch (e) {
      debugPrint('Backup: $e');
      note = 'Something went wrong ($e). Nothing was changed.';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirmRestore = false;
      _note = note ?? '';
      _failed = failed;
    });
  }

  Future<String?> _save() async {
    final before = appDb.setting<String?>('last_backup', null);
    // Recorded first so the backup itself remembers when it was made.
    await appDb.setSetting('last_backup', todayKey());
    final bytes = await appDb.exportBackup();
    final saved = await saveBackupFile('HYETI backup ${todayKey()}.hyeti', bytes);
    if (!saved) {
      await appDb.setSetting('last_backup', before);
      return null;
    }
    return 'Backup saved. Keep it somewhere off this phone.';
  }

  Future<String?> _restore() async {
    final bytes = await pickBackupFile();
    if (bytes == null) return null;
    await appDb.importBackup(bytes);
    return 'Restored. Everything is as it was when that backup was made.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormColumn(
      children: [
        T(backupSummary(), variant: TextVariant.heading, color: backupDue() ? c.warn : null),
        const T(
          'A backup is one file with everything in HYETI: calendar, workouts, meals, wallet, watch list, notes, '
          'sketches and settings. Save it somewhere off this phone, like Google Drive, iCloud Drive or a message to '
          'yourself. It also moves your data to a new phone, Android or iPhone.',
          dim: true,
        ),
        AppButton(
          _busy && !_confirmRestore ? 'Saving…' : 'Save a backup',
          icon: Icons.save_alt,
          onPressed: _busy ? null : () => _run(_save),
        ),
        if (!_confirmRestore)
          AppButton(
            'Restore from a backup',
            kind: ButtonKind.soft,
            icon: Icons.restore,
            onPressed: _busy ? null : () => setState(() => _confirmRestore = true),
          )
        else ...[
          T('Restoring replaces everything on this phone with what is in the backup.', color: c.warn),
          Row(
            spacing: Spacing.sm,
            children: [
              Expanded(
                child: AppButton(
                  'Cancel',
                  kind: ButtonKind.soft,
                  onPressed: _busy ? null : () => setState(() => _confirmRestore = false),
                ),
              ),
              Expanded(
                child: AppButton(
                  _busy ? 'Restoring…' : 'Choose the file',
                  icon: Icons.folder_open,
                  onPressed: _busy ? null : () => _run(_restore),
                ),
              ),
            ],
          ),
        ],
        if (_note.isNotEmpty) T(_note, color: _failed ? c.danger : c.success),
      ],
    );
  }
}
