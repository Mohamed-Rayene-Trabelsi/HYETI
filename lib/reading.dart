import 'dart:convert';

import 'date.dart';
import 'db.dart';
import 'genres.dart';
import 'watch_api.dart' show httpClient;

/// The reading list: manga, manhwa and manhua with the chapter reached, and its CSV import and export.

const readingKinds = {'manga': 'Manga', 'manhwa': 'Manhwa', 'manhua': 'Manhua', 'novel': 'Novel'};
const readingStatuses = {
  'reading': 'Reading',
  'plan': 'Plan to read',
  'completed': 'Completed',
  'paused': 'On hold',
  'dropped': 'Dropped',
};

/// One title as read from a CSV row, before it is on the list.
class ReadingEntry {
  const ReadingEntry({
    required this.title,
    this.kind = 'manga',
    this.status = 'reading',
    this.chapter = 0,
    this.total,
    this.link = '',
    this.extId,
    this.genres = const [],
  });

  final String title;
  final String kind;
  final String status;
  final double chapter;
  final int? total;
  final String link;
  final String? extId;
  final List<String> genres;
}

/// Two reading titles are the same one when this matches: case, spaces and punctuation are ignored.
String readingKey(String title) => watchTitleKey('read', title);

/* ---------- CSV ---------- */

/// Splits CSV text into rows of fields. Handles quoted fields (with commas, quotes and line breaks inside),
/// Windows line ends and a leading byte-order mark. The separator is whichever of comma, semicolon or tab the
/// first line uses most, since spreadsheets in some countries save with semicolons.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final sep = [
    ',',
    ';',
    '\t',
  ].reduce((a, b) => b.allMatches(firstLine).length > a.allMatches(firstLine).length ? b : a);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  return rows;
}

String _csvField(Object? value) {
  final s = '${value ?? ''}';
  return s.contains(RegExp('[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

const csvColumns = ['title', 'type', 'status', 'chapter', 'total_chapters', 'link', 'anilist_id', 'genres'];

/// The reading list as CSV, one title per row under a header of [csvColumns].
String readingToCsv(List<Rec> rows) {
  final lines = [
    csvColumns.join(','),
    for (final r in rows)
      [
        r['title'],
        r['kind'],
        r['status'],
        _number((r['chapter'] as num?) ?? 0),
        r['total'],
        r['link'],
        switch (r['ext_id']) {
          final String id when id.startsWith('anilist:') => id.substring('anilist:'.length),
          _ => '',
        },
        parseGenres(r['genres']).join('; '),
      ].map(_csvField).join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}

String _number(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// Header names other trackers use, squashed to letters and digits, and the column each one means.
const _headers = {
  'title': ['title', 'name', 'manga', 'series', 'seriestitle', 'mangatitle', 'seriesname'],
  'chapter': [
    'chapter', 'chapters read', 'chaptersread', 'progress', 'read', 'lastread', 'lastchapter', 'currentchapter',
    'myreadchapters', 'readchapters', 'chapterread', //
  ],
  'total': ['total', 'totalchapters', 'chapters', 'serieschapters', 'chaptercount', 'maxchapter'],
  'status': ['status', 'mystatus', 'readingstatus', 'state'],
  'kind': ['type', 'kind', 'format', 'seriestype', 'category'],
  'link': ['link', 'url', 'source', 'sourceurl', 'website'],
  'anilist': ['anilistid', 'anilist', 'idanilist'],
  'genres': ['genres', 'genre'],
};

String _squash(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

String _status(String raw, double chapter) {
  final s = _squash(raw);
  if (s.isEmpty) return chapter > 0 ? 'reading' : 'plan';
  if (s.contains('plan') || s == 'ptr' || s.contains('want') || s.contains('later')) return 'plan';
  if (s.contains('complet') || s.contains('finish') || s == 'done') return 'completed';
  if (s.contains('hold') || s.contains('pause')) return 'paused';
  if (s.contains('drop')) return 'dropped';
  return 'reading';
}

String _kind(String raw) {
  final s = _squash(raw);
  if (s.contains('manhwa') || s.contains('korea') || s.contains('webtoon')) return 'manhwa';
  if (s.contains('manhua') || s.contains('chin')) return 'manhua';
  if (s.contains('novel')) return 'novel';
  return 'manga';
}

/// The first number in [raw] ("Ch. 45.5" → 45.5), or null.
double? _firstNumber(String raw) =>
    double.tryParse(RegExp(r'\d+(?:[.,]\d+)?').stringMatch(raw)?.replaceAll(',', '.') ?? '');

/// The titles in a CSV file. The columns are found by their header, under the names this app and other
/// trackers use; with no header the columns are taken to be in this app's order ([csvColumns]).
/// Rows without a title are skipped.
List<ReadingEntry> parseReadingCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return [];
  final header = rows.first.map(_squash).toList();
  final at = <String, int>{};
  for (final MapEntry(key: column, value: names) in _headers.entries) {
    final i = header.indexWhere((h) => names.map(_squash).contains(h));
    if (i >= 0) at[column] = i;
  }
  final hasHeader = at.containsKey('title');
  if (!hasHeader) {
    at
      ..clear()
      ..addAll({'title': 0, 'kind': 1, 'status': 2, 'chapter': 3, 'total': 4, 'link': 5, 'anilist': 6, 'genres': 7});
  }
  String cell(List<String> row, String column) {
    final i = at[column];
    return i != null && i < row.length ? row[i].trim() : '';
  }

  return [
    for (final row in hasHeader ? rows.skip(1) : rows)
      if (cell(row, 'title').isNotEmpty)
        () {
          final chapter = _firstNumber(cell(row, 'chapter')) ?? 0;
          final total = _firstNumber(cell(row, 'total'))?.round();
          final anilist = int.tryParse(cell(row, 'anilist'));
          return ReadingEntry(
            title: cell(row, 'title'),
            kind: _kind(cell(row, 'kind')),
            status: _status(cell(row, 'status'), chapter),
            chapter: chapter,
            total: total != null && total > 0 ? total : null,
            link: cell(row, 'link'),
            extId: anilist == null ? null : 'anilist:$anilist',
            genres: [
              for (final g in cell(row, 'genres').split(RegExp('[;,|]')))
                if (genresFor('manga').contains(g.trim())) g.trim(),
            ],
          );
        }(),
  ];
}

/// Puts [entries] on the reading list. A title already there (the same AniList id, or the same name) is updated
/// rather than added twice, and keeps whichever chapter is further along, so an old file never undoes reading.
Future<({int added, int updated})> importReading(List<ReadingEntry> entries) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  return appDb.transaction((txn) async {
    final existing = await txn.rawQuery('SELECT * FROM reading');
    final byExt = {
      for (final r in existing)
        if (r['ext_id'] case final String id) id: r,
    };
    final byTitle = {for (final r in existing) readingKey(r['title'] as String): r};
    var added = 0, updated = 0;
    for (final e in entries) {
      final old = (e.extId == null ? null : byExt[e.extId]) ?? byTitle[readingKey(e.title)];
      if (old == null) {
        final id = await txn.rawInsert(
          'INSERT OR IGNORE INTO reading (title, kind, status, chapter, total, link, ext_id, genres, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [e.title, e.kind, e.status, e.chapter, e.total, e.link, e.extId, joinGenres(e.genres), now],
        );
        final row = {'id': id, 'title': e.title, 'ext_id': e.extId};
        byTitle[readingKey(e.title)] = row;
        if (e.extId != null) byExt[e.extId!] = row;
        added++;
        continue;
      }
      final chapter = e.chapter > ((old['chapter'] as num?) ?? 0) ? e.chapter : (old['chapter'] as num?) ?? 0;
      await txn.execute(
        'UPDATE OR IGNORE reading SET kind = ?, status = ?, chapter = ?, total = COALESCE(?, total), '
        "link = CASE WHEN ? = '' THEN link ELSE ? END, ext_id = COALESCE(ext_id, ?), genres = COALESCE(?, genres), "
        'updated_at = ? WHERE id = ?',
        [e.kind, e.status, chapter, e.total, e.link, e.link, e.extId, joinGenres(e.genres), now, old['id']],
      );
      updated++;
    }
    return (added: added, updated: updated);
  });
}

/* ---------- Import from a link ---------- */

/// The address to download for a link the person pasted. A file shown on GitHub or GitLab, or a gist, is
/// turned into its raw form, so a list kept in a repository can be pasted as it appears in the browser.
/// Null when it is not a web address.
Uri? csvLinkUri(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) return null;
  final parts = uri.pathSegments;
  // github.com/<user>/<repo>/blob/<branch>/<path> → raw.githubusercontent.com/<user>/<repo>/<branch>/<path>
  if (uri.host == 'github.com' && parts.length > 4 && parts[2] == 'blob') {
    return Uri.https('raw.githubusercontent.com', [...parts.take(2), ...parts.skip(3)].join('/'));
  }
  // gist.github.com/<user>/<id> → its raw text
  if (uri.host == 'gist.github.com' && parts.length == 2) {
    return Uri.https('gist.githubusercontent.com', '${parts.join('/')}/raw');
  }
  // gitlab.com/<group>/<repo>/-/blob/<branch>/<path> → …/-/raw/…
  if (uri.host == 'gitlab.com' && parts.contains('blob')) {
    return uri.replace(pathSegments: [for (final p in parts) p == 'blob' ? 'raw' : p]);
  }
  return uri;
}

class LinkError implements Exception {
  const LinkError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads the CSV file at [link] and reads its titles.
Future<List<ReadingEntry>> fetchReadingCsv(String link) async {
  final uri = csvLinkUri(link);
  if (uri == null) throw const LinkError('That is not a web address. It should start with https://');
  final res = await httpClient.get(uri).timeout(const Duration(seconds: 20));
  if (res.statusCode == 404) throw const LinkError('Nothing is at that address. Is the repository public?');
  if (res.statusCode != 200) throw LinkError('The site answered ${res.statusCode}.');
  final text = utf8.decode(res.bodyBytes, allowMalformed: true);
  if (text.trimLeft().startsWith('<')) {
    throw const LinkError('That link opens a web page, not a CSV file. Use the link to the file itself ("Raw").');
  }
  final entries = parseReadingCsv(text);
  if (entries.isEmpty) throw const LinkError('No titles were found in that file.');
  return entries;
}

/// The file name an export is offered under.
String readingFileName() => 'hyeti-reading-${todayKey()}.csv';
