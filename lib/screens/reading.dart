import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../genre_picker.dart';
import '../genres.dart';
import '../reading.dart';
import '../theme.dart';
import '../ui.dart';
import '../watch_api.dart';
import 'watch.dart' show WatchPoster;

/// The Manga part of the Watch tab: the reading list with the chapter reached, a search of AniList to add to it,
/// and CSV import and export.
class ReadingView extends StatefulWidget {
  const ReadingView({super.key});

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<ReadingView> with Live {
  List<Rec> _rows = [];

  /// A status to show only, or null for all.
  String? _status;
  String? _genre;

  final _text = TextEditingController();
  Timer? _typing;
  int _request = 0;
  bool _loading = false;
  String _error = '';
  List<FoundManga> _found = [];
  final _adding = <String>{};

  @override
  Future<void> load() async {
    _rows = await appDb.query(
      "SELECT * FROM reading ORDER BY CASE status WHEN 'reading' THEN 0 WHEN 'plan' THEN 1 WHEN 'paused' THEN 2 "
      "WHEN 'completed' THEN 3 ELSE 4 END, updated_at DESC",
    );
  }

  @override
  void dispose() {
    _request = -1;
    _typing?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onTyped(String value) {
    _typing?.cancel();
    final term = value.trim();
    setState(() {
      if (term.length < 2) {
        _found = [];
        _error = '';
        _loading = false;
      }
    });
    if (term.length < 2) return;
    _typing = Timer(const Duration(milliseconds: 400), () => _search(term));
  }

  Future<void> _search(String term) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final page = await fetchManga(term);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _found = page.items;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Check your internet connection and try again.';
      });
    }
  }

  void _clearSearch() {
    _text.clear();
    _request++;
    setState(() {
      _found = [];
      _loading = false;
      _error = '';
    });
  }

  Rec? _onList(FoundManga f) => _rows
      .where(
        (r) =>
            r['ext_id'] == f.extId || (r['ext_id'] == null && readingKey(r['title'] as String) == readingKey(f.title)),
      )
      .firstOrNull;

  Future<void> _add(FoundManga f) async {
    if (!_adding.add(f.extId)) return;
    setState(() {});
    try {
      await importReading([
        ReadingEntry(title: f.title, kind: f.kind, status: 'plan', total: f.chapters, extId: f.extId, genres: f.genres),
      ]);
      // The poster only comes from the search, never from a file.
      await appDb.run('UPDATE reading SET poster = ? WHERE ext_id = ?', [f.poster, f.extId]);
    } finally {
      if (mounted) setState(() => _adding.remove(f.extId));
    }
  }

  /// One chapter on (or back with [by] -1). The first chapter starts a planned title; the last finishes it.
  Future<void> _step(Rec r, int by) async {
    final total = r['total'] as int?;
    final now = ((r['chapter'] as num?) ?? 0).toDouble();
    var chapter = (now + by).clamp(0, double.infinity).toDouble();
    // 12.5 goes to 13 and back to 12, so the half chapter does not stick.
    if (now != now.roundToDouble()) chapter = by > 0 ? now.ceilToDouble() : now.floorToDouble();
    var status = r['status'] as String;
    if (by > 0 && (status == 'plan' || status == 'paused')) status = 'reading';
    if (total != null && chapter >= total) status = 'completed';
    if (by < 0 && status == 'completed' && (total == null || chapter < total)) status = 'reading';
    tick();
    await appDb.run('UPDATE reading SET chapter = ?, status = ?, updated_at = ? WHERE id = ?', [
      chapter,
      status,
      DateTime.now().millisecondsSinceEpoch,
      r['id'],
    ]);
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searching = _text.text.trim().length >= 2;
    final counts = <String, int>{};
    for (final r in _rows) {
      counts[r['status'] as String] = (counts[r['status'] as String] ?? 0) + 1;
    }
    final genres = {for (final r in _rows) ...parseGenres(r['genres'])}.toList()..sort();
    final genre = genres.contains(_genre) ? _genre : null;
    final status = counts.containsKey(_status) ? _status : null;
    final shown = [
      for (final r in _rows)
        if ((status == null || r['status'] == status) && (genre == null || parseGenres(r['genres']).contains(genre))) r,
    ];
    final spinner = Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
      child: Center(child: CircularProgressIndicator(color: c.accent)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        Field(
          controller: _text,
          icon: Icons.search,
          hint: 'Search manga, manhwa, manhua',
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        if (searching) ...[
          Wrap(
            children: [AppChip('Clear search', icon: Icons.close, onPressed: _clearSearch)],
          ),
          if (_loading) spinner,
          if (!_loading && _error.isEmpty && _found.isEmpty)
            const Empty(
              icon: Icons.search_off,
              title: 'Nothing found',
              hint: 'Check the spelling, or try the original title.',
            ),
          for (final f in _found) _foundCard(f),
          if (_error.isNotEmpty)
            Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Could not search',
              hint: _error,
              action: AppButton('Try again', kind: ButtonKind.soft, onPressed: () => _search(_text.text.trim())),
            ),
          const T('Data from AniList', variant: TextVariant.small, dim: true, align: TextAlign.center),
        ] else ...[
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (counts.length > 1) ...[
                AppChip(
                  'All ${_rows.length}',
                  selected: status == null,
                  onPressed: () => setState(() => _status = null),
                ),
                for (final MapEntry(key: s, value: label) in readingStatuses.entries)
                  if (counts.containsKey(s))
                    AppChip(
                      '$label ${counts[s]}',
                      selected: status == s,
                      onPressed: () => setState(() => _status = status == s ? null : s),
                    ),
              ],
              if (genres.isNotEmpty)
                GenreChip(options: genres, value: genre, onChanged: (g) => setState(() => _genre = g)),
              AppChip('Import / export', icon: Icons.import_export, onPressed: () => openReadingTransfer(context)),
            ],
          ),
          if (ready && _rows.isEmpty)
            Empty(
              icon: Icons.menu_book_outlined,
              title: 'Nothing on your reading list',
              hint:
                  'Search above to add a manga, manhwa or manhua, or bring in a list you keep elsewhere as a CSV file.',
              action: AppButton('Import a list', kind: ButtonKind.soft, onPressed: () => openReadingTransfer(context)),
            ),
          if (_rows.isNotEmpty && shown.isEmpty)
            const Empty(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing matches',
              hint: 'Try another genre or status.',
            ),
          for (final r in shown) _rowCard(r),
        ],
      ],
    );
  }

  Widget _foundCard(FoundManga f) {
    final c = context.colors;
    final on = _onList(f);
    return AppCard(
      children: [
        Row(
          spacing: Spacing.md,
          children: [
            WatchPoster(url: f.poster, kind: 'read'),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  T(f.title, variant: TextVariant.heading, maxLines: 2),
                  T(f.note, variant: TextVariant.small, dim: true, maxLines: 2),
                  if (f.genres.isNotEmpty)
                    T(f.genres.take(3).join(' · '), variant: TextVariant.small, dim: true, maxLines: 1),
                ],
              ),
            ),
            if (on != null)
              AppChip(
                'On list',
                icon: Icons.check,
                selected: true,
                color: c.success,
                onPressed: () => openReadingEdit(context, on),
              )
            else
              AppButton(
                'Add',
                icon: Icons.add,
                kind: ButtonKind.soft,
                small: true,
                onPressed: _adding.contains(f.extId) ? null : () => _add(f),
              ),
          ],
        ),
      ],
    );
  }

  Widget _rowCard(Rec r) {
    final c = context.colors;
    final chapter = ((r['chapter'] as num?) ?? 0).toDouble();
    final total = r['total'] as int?;
    final status = r['status'] as String;
    final link = r['link'] as String? ?? '';
    final finished = total != null && chapter >= total;
    final progress = chapter == 0
        ? (status == 'plan' ? 'Not started' : 'No chapter yet')
        : total != null
        ? 'Chapter ${plainNumber(chapter)} of $total'
        : 'Chapter ${plainNumber(chapter)}';
    return AppCard(
      onTap: () => openReadingEdit(context, r),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Spacing.md,
          children: [
            WatchPoster(url: r['poster'] as String?, kind: 'read'),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  T(r['title'] as String, variant: TextVariant.heading, maxLines: 2),
                  T(
                    '${readingKinds[r['kind']] ?? 'Manga'} · ${readingStatuses[status] ?? status}',
                    variant: TextVariant.small,
                    dim: true,
                    maxLines: 1,
                  ),
                  T(progress, variant: TextVariant.label, color: status == 'completed' ? c.success : c.text),
                  if (total != null && total > 0) ...[
                    const SizedBox(height: 4),
                    ProgressBar(chapter / total, color: status == 'completed' ? c.success : c.accent),
                  ],
                ],
              ),
            ),
          ],
        ),
        Row(
          spacing: Spacing.sm,
          children: [
            Semantics(
              label: 'One chapter back',
              excludeSemantics: true,
              child: AppButton(
                '−1',
                kind: ButtonKind.soft,
                small: true,
                onPressed: chapter > 0 ? () => _step(r, -1) : null,
              ),
            ),
            Expanded(
              child: AppButton(
                finished ? 'Finished' : '+1 chapter',
                icon: finished ? Icons.check : null,
                small: true,
                onPressed: finished ? null : () => _step(r, 1),
              ),
            ),
            if (link.isNotEmpty)
              AppButton(
                'Open',
                icon: Icons.open_in_new,
                kind: ButtonKind.plain,
                small: true,
                onPressed: () => _openLink(link),
              ),
          ],
        ),
      ],
    );
  }
}

/// The sheet to add a title by hand ([row] null) or change one on the list.
Future<void> openReadingEdit(BuildContext context, [Rec? row]) => showSheet(
  context,
  title: row == null ? 'Add to reading list' : 'Edit',
  builder: (sheet) => _ReadingForm(row: row, done: () => Navigator.pop(sheet)),
);

class _ReadingForm extends StatefulWidget {
  const _ReadingForm({required this.row, required this.done});

  final Rec? row;
  final VoidCallback done;

  @override
  State<_ReadingForm> createState() => _ReadingFormState();
}

class _ReadingFormState extends State<_ReadingForm> {
  late final _title = TextEditingController(text: widget.row?['title'] as String? ?? '');
  late final _chapter = TextEditingController(
    text: widget.row == null ? '' : plainNumber((widget.row!['chapter'] as num?) ?? 0),
  );
  late final _total = TextEditingController(text: '${widget.row?['total'] ?? ''}');
  late final _link = TextEditingController(text: widget.row?['link'] as String? ?? '');
  late String _kind = widget.row?['kind'] as String? ?? 'manga';
  late String _status = widget.row?['status'] as String? ?? 'reading';
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    _chapter.dispose();
    _total.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Give it a title.');
    final chapterText = _chapter.text.trim().replaceFirst(',', '.');
    final chapter = chapterText.isEmpty ? 0.0 : double.tryParse(chapterText);
    if (chapter == null || chapter < 0) {
      return setState(() => _error = 'The chapter should be a number, like 12 or 12.5.');
    }
    final totalText = _total.text.trim();
    final total = totalText.isEmpty ? null : int.tryParse(totalText);
    if (totalText.isNotEmpty && (total == null || total <= 0)) {
      return setState(() => _error = 'Total chapters should be a whole number, or left empty.');
    }
    final link = _link.text.trim();
    if (link.isNotEmpty && csvLinkUri(link) == null) {
      return setState(() => _error = 'The link should start with https://');
    }
    final status = total != null && chapter >= total ? 'completed' : _status;
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = widget.row;
    if (row == null) {
      final titles = await appDb.query('SELECT title FROM reading');
      if (titles.any((r) => readingKey(r['title'] as String) == readingKey(title))) {
        return setState(() => _error = '$title is already on your list.');
      }
      await appDb.insert(
        'INSERT INTO reading (title, kind, status, chapter, total, link, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [title, _kind, status, chapter, total, link, now],
      );
    } else {
      await appDb.run(
        'UPDATE reading SET title = ?, kind = ?, status = ?, chapter = ?, total = ?, link = ?, updated_at = ? WHERE id = ?',
        [title, _kind, status, chapter, total, link, now, row['id']],
      );
    }
    widget.done();
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        if (widget.row == null)
          const T(
            'Or search above to add it from AniList, with its cover and chapter count.',
            variant: TextVariant.small,
            dim: true,
          ),
        Field(
          label: 'Title',
          controller: _title,
          hint: 'Solo Leveling',
          textInputAction: TextInputAction.next,
          autofocus: widget.row == null,
        ),
        Segmented<String>(value: _kind, onChanged: (v) => setState(() => _kind = v), options: readingKinds),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final MapEntry(key: s, value: label) in readingStatuses.entries)
              AppChip(label, selected: _status == s, onPressed: () => setState(() => _status = s)),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: Field(
                label: 'Chapter reached',
                controller: _chapter,
                hint: '0',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            Expanded(
              child: Field(
                label: 'Total (optional)',
                controller: _total,
                hint: 'Ongoing',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        Field(
          label: 'Where you read it (optional)',
          controller: _link,
          hint: 'https://…',
          keyboardType: TextInputType.url,
          capitalization: TextCapitalization.none,
          autocorrect: false,
        ),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Save', onPressed: _save),
        if (widget.row != null)
          AppButton(
            'Remove from list',
            kind: ButtonKind.danger,
            onPressed: () async {
              await deleteWithUndo('reading', widget.row!, 'Removed ${widget.row!['title']}');
              widget.done();
            },
          ),
      ],
    );
  }
}

/* ---------- Import and export ---------- */

/// Replaceable in tests, which have no file dialogs.
Future<String?> Function() pickCsvText = () async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
  if (file == null) return null;
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
};

/// Replaceable in tests. True when the file was saved.
Future<bool> Function(String name, String text) saveCsvText = (name, text) async {
  final uri = await FilePicker.saveFile(
    fileName: name,
    bytes: Uint8List.fromList(utf8.encode(text)),
    mimeType: 'text/csv',
  );
  return uri != null;
};

/// The sheet for moving the reading list in and out as CSV: a file on the phone, the clipboard, or a link.
Future<void> openReadingTransfer(BuildContext context) =>
    showSheet(context, title: 'Import and export', builder: (sheet) => const _Transfer());

class _Transfer extends StatefulWidget {
  const _Transfer();

  @override
  State<_Transfer> createState() => _TransferState();
}

class _TransferState extends State<_Transfer> {
  late final _link = TextEditingController(text: appDb.setting('reading_link', ''));
  bool _busy = false;

  /// What the last action did, and whether it went wrong.
  String _note = '';
  bool _failed = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    String note;
    var failed = false;
    try {
      note = await action();
    } catch (e) {
      note = e is LinkError ? e.message : 'That did not work ($e).';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = note;
      _failed = failed;
    });
  }

  String _report(({int added, int updated}) r) => switch (r) {
    (added: 0, updated: 0) => 'Nothing new in that list.',
    (added: final a, updated: 0) => 'Added $a ${a == 1 ? 'title' : 'titles'}.',
    (added: 0, updated: final u) => 'Updated $u ${u == 1 ? 'title' : 'titles'}.',
    (added: final a, updated: final u) => 'Added $a, updated $u.',
  };

  Future<String> _importText(String? text) async {
    if (text == null) return _note;
    final entries = parseReadingCsv(text);
    if (entries.isEmpty) throw const LinkError('No titles were found. The file needs a "title" column.');
    return _report(await importReading(entries));
  }

  Future<String> _fromLink() async {
    final link = _link.text.trim();
    if (link.isEmpty) throw const LinkError('Paste the link to a CSV file first.');
    final report = _report(await importReading(await fetchReadingCsv(link)));
    // Kept, so the same list can be pulled in again later with one tap.
    await appDb.setSetting('reading_link', link);
    return report;
  }

  Future<String> _csv() async => readingToCsv(await appDb.query('SELECT * FROM reading ORDER BY title COLLATE NOCASE'));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saved = appDb.setting('reading_link', '');
    return FormColumn(
      children: [
        const T('EXPORT', variant: TextVariant.label, dim: true),
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: AppButton(
                'Save CSV file',
                icon: Icons.download_outlined,
                kind: ButtonKind.soft,
                onPressed: _busy
                    ? null
                    : () => _run(() async => await saveCsvText(readingFileName(), await _csv()) ? 'Saved.' : _note),
              ),
            ),
            Expanded(
              child: AppButton(
                'Copy CSV',
                icon: Icons.copy_outlined,
                kind: ButtonKind.soft,
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await Clipboard.setData(ClipboardData(text: await _csv()));
                        return 'Copied. Paste it into a spreadsheet or a file.';
                      }),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        const T('IMPORT', variant: TextVariant.label, dim: true),
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: AppButton(
                'Open CSV file',
                icon: Icons.upload_file_outlined,
                kind: ButtonKind.soft,
                onPressed: _busy ? null : () => _run(() async => _importText(await pickCsvText())),
              ),
            ),
            Expanded(
              child: AppButton(
                'Paste CSV',
                icon: Icons.content_paste,
                kind: ButtonKind.soft,
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                        if (text == null || text.trim().isEmpty) throw const LinkError('The clipboard is empty.');
                        return _importText(text);
                      }),
              ),
            ),
          ],
        ),
        Field(
          label: 'From a link',
          controller: _link,
          hint: 'https://github.com/you/lists/blob/main/reading.csv',
          keyboardType: TextInputType.url,
          capitalization: TextCapitalization.none,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _run(_fromLink),
        ),
        AppButton(
          _busy
              ? 'Working…'
              : (saved.isNotEmpty && saved == _link.text.trim() ? 'Update from link' : 'Import from link'),
          icon: Icons.link,
          onPressed: _busy ? null : () => _run(_fromLink),
        ),
        if (_note.isNotEmpty) T(_note, color: _failed ? c.danger : c.success),
        const T(
          'Columns: title, type, status, chapter, total_chapters, link. Lists from other trackers work too, as long as '
          'they have a title column. A link can point at a file in a public GitHub repository or gist; the link is '
          'kept so you can update from it again. Titles already on your list keep whichever chapter is further along.',
          variant: TextVariant.small,
          dim: true,
        ),
      ],
    );
  }
}
