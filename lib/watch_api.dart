import 'dart:convert';

import 'package:http/http.dart' as http;

import 'date.dart';
import 'db.dart';

/// Replaceable in tests.
http.Client httpClient = http.Client();

const _timeout = Duration(seconds: 15);

/// A title found online, not saved to the list yet.
class Found {
  const Found({
    required this.extId,
    required this.kind,
    required this.title,
    required this.releaseDate,
    this.startMin,
    required this.note,
    required this.rating,
    this.poster,
  });

  /// Address of a small poster image, when the source has one.
  final String? poster;

  final String extId;

  /// 'anime', 'movie', 'series' or 'match'.
  final String kind;
  final String title;
  final String? releaseDate;

  /// Local air or kick-off time in minutes, when the source knows it (anime and matches).
  final int? startMin;

  /// Episode or premiere note, e.g. "Episode 7 · 16:30".
  final String note;

  /// e.g. "IMDb 8.1" or "TMDB 7.6"; empty when unrated.
  final String rating;
}

/// A service refused the key it was given.
class KeyError implements Exception {
  const KeyError(this.message);
  final String message;
}

/// One page of titles found online, and whether a further page exists.
typedef FoundPage = ({List<Found> items, bool more});

/* ---------- Anime: AniList, no key ---------- */

const _anilistQuery = r'''
query ($search: String, $page: Int, $sort: [MediaSort], $status: [MediaStatus]) {
  Page(page: $page, perPage: 20) {
    pageInfo { hasNextPage }
    media(type: ANIME, search: $search, sort: $sort, status_in: $status, isAdult: false) {
      id
      title { romaji english }
      averageScore
      status
      format
      episodes
      nextAiringEpisode { airingAt episode }
      startDate { year month day }
      coverImage { medium }
    }
  }
}''';

const _anilistNextQuery = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) { nextAiringEpisode { airingAt episode } }
}''';

Future<Map<String, dynamic>> _anilist(String query, Map<String, Object?> variables) async {
  final res = await httpClient
      .post(
        Uri.https('graphql.anilist.co', '/'),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}),
      )
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('AniList answered ${res.statusCode}');
  return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
}

/// For an anime on the list: the date and label of its next episode, if one is scheduled.
Future<({String date, String note})?> nextAnimeEpisode(String extId) async {
  final data = await _anilist(_anilistNextQuery, {'id': int.parse(extId.split(':')[1])});
  final next = (data['Media'] as Map<String, dynamic>?)?['nextAiringEpisode'] as Map<String, dynamic>?;
  if (next == null) return null;
  final at = DateTime.fromMillisecondsSinceEpoch((next['airingAt'] as int) * 1000);
  return (date: toKey(at), note: 'Episode ${next['episode']} · ${formatTime(at.hour * 60 + at.minute)}');
}

/// What to say about an anime with no scheduled episode.
String _animeNote(Map<String, dynamic> m, {required bool dated}) {
  final episodes = m['episodes'] as int?;
  final format = switch (m['format']) {
    'MOVIE' => 'Movie',
    'OVA' || 'ONA' => m['format'] as String,
    'SPECIAL' => 'Special',
    _ => '',
  };
  final state = switch (m['status']) {
    'FINISHED' => episodes != null && episodes > 1 ? 'Finished · $episodes episodes' : 'Finished',
    'RELEASING' => 'Airing',
    'CANCELLED' => 'Cancelled',
    'HIATUS' => 'On hiatus',
    _ => dated ? 'Premiere' : 'Date not announced',
  };
  return [if (format.isNotEmpty) format, state].join(' · ');
}

/// Page [page] (from 1) of anime. With no [search]: trending shows that are airing or about to.
/// With one: the closest matches among all anime, finished ones included.
Future<FoundPage> fetchAnime(String search, {int page = 1}) async {
  final data = await _anilist(_anilistQuery, {
    'page': page,
    if (search.isNotEmpty) ...{
      'search': search,
      'sort': ['SEARCH_MATCH', 'POPULARITY_DESC'],
    } else ...{
      'sort': ['TRENDING_DESC'],
      'status': ['RELEASING', 'NOT_YET_RELEASED'],
    },
  });
  final result = data['Page'] as Map<String, dynamic>;
  final media = result['media'] as List;
  final more = (result['pageInfo'] as Map<String, dynamic>?)?['hasNextPage'] == true;
  final items = [
    for (final m in media.cast<Map<String, dynamic>>())
      () {
        final extId = 'anilist:${m['id']}';
        final poster = (m['coverImage'] as Map<String, dynamic>?)?['medium'] as String?;
        final title = (m['title']['english'] ?? m['title']['romaji'] ?? 'Untitled') as String;
        final score = m['averageScore'] as num?;
        final rating = score != null && score > 0 ? 'AniList ${(score / 10).toStringAsFixed(1)}' : '';
        final next = m['nextAiringEpisode'] as Map<String, dynamic>?;
        if (next != null) {
          final at = DateTime.fromMillisecondsSinceEpoch((next['airingAt'] as int) * 1000);
          final min = at.hour * 60 + at.minute;
          return Found(
            extId: extId,
            kind: 'anime',
            title: title,
            rating: rating,
            poster: poster,
            releaseDate: toKey(at),
            startMin: min,
            note: 'Episode ${next['episode']} · ${formatTime(min)}',
          );
        }
        final start = m['startDate'] as Map<String, dynamic>;
        final year = start['year'] as int?, month = start['month'] as int?, day = start['day'] as int?;
        final known = year != null && month != null && day != null;
        return Found(
          extId: extId,
          kind: 'anime',
          title: title,
          rating: rating,
          poster: poster,
          releaseDate: known ? toKey(DateTime(year, month, day)) : null,
          note: _animeNote(m, dated: known),
        );
      }(),
  ];
  return (items: items, more: more);
}

/* ---------- Movies and series: TMDB for the lists, OMDb for IMDb ratings ---------- */

Future<Map<String, dynamic>> _tmdb(String path, String key, [Map<String, String> params = const {}]) async {
  // TMDB issues two credentials: a short "API key" and a long "read access token". Accept either.
  final isToken = key.contains('.');
  final res = await httpClient
      .get(
        Uri.https('api.themoviedb.org', '/3$path', isToken ? params : {...params, 'api_key': key}),
        headers: {'Accept': 'application/json', if (isToken) 'Authorization': 'Bearer $key'},
      )
      .timeout(_timeout);
  if (res.statusCode == 401) throw const KeyError('TMDB did not accept that key.');
  if (res.statusCode != 200) throw Exception('TMDB answered ${res.statusCode}');
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}

String _tmdbType(String kind) => kind == 'movie' ? 'movie' : 'tv';

/// IMDb rating for one title, from the local cache or OMDb. Null when there is none.
Future<String?> _imdbRating(String kind, int id, String tmdbKey, String omdbKey) async {
  final cacheKey = '$kind:$id';
  final cached = await appDb.query('SELECT rating, fetched FROM ratings WHERE key = ?', [cacheKey]);
  if (cached.isNotEmpty && daysBetween(cached.first['fetched'] as String, todayKey()) < 7) {
    return cached.first['rating'] as String?;
  }

  final ids = await _tmdb('/${_tmdbType(kind)}/$id/external_ids', tmdbKey);
  final imdbId = ids['imdb_id'] as String?;
  String? rating;
  if (imdbId != null && imdbId.isNotEmpty) {
    final res = await httpClient
        .get(Uri.https('www.omdbapi.com', '/', {'apikey': omdbKey, 'i': imdbId}))
        .timeout(_timeout);
    if (res.statusCode == 401) throw const KeyError('OMDb did not accept that key.');
    if (res.statusCode != 200) throw Exception('OMDb answered ${res.statusCode}');
    final value = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['imdbRating'] as String?;
    if (value != null && value.isNotEmpty && value != 'N/A') rating = value;
  }
  // Written straight to the database: a cache entry is not something screens need to redraw for.
  await appDb.raw.execute('INSERT OR REPLACE INTO ratings (key, rating, fetched) VALUES (?, ?, ?)', [
    cacheKey,
    rating,
    todayKey(),
  ]);
  return rating;
}

/// Hot (trending this week) or upcoming movies / series, each with a rating.
/// [mode] is 'hot' or 'upcoming'; a non-empty [search] overrides it. [page] counts from 1.
Future<FoundPage> fetchTitles(
  String kind,
  String mode,
  String search, {
  required String tmdbKey,
  required String omdbKey,
  int page = 1,
}) async {
  final type = _tmdbType(kind);
  final today = todayKey();
  final at = {'page': '$page'};
  final Map<String, dynamic> result;
  if (search.isNotEmpty) {
    result = await _tmdb('/search/$type', tmdbKey, {'query': search, ...at});
  } else if (mode == 'hot') {
    result = await _tmdb('/trending/$type/week', tmdbKey, at);
  } else {
    // Popular titles whose first release falls in the next three months.
    final dateField = kind == 'movie' ? 'primary_release_date' : 'first_air_date';
    result = await _tmdb('/discover/$type', tmdbKey, {
      'sort_by': 'popularity.desc',
      '$dateField.gte': today,
      '$dateField.lte': addDays(today, 90),
      ...at,
    });
  }

  final more = page < ((result['total_pages'] as num?) ?? 1);
  final items = (result['results'] as List).cast<Map<String, dynamic>>();
  final found = await Future.wait([
    for (final item in items)
      () async {
        final rawDate = (kind == 'movie' ? item['release_date'] : item['first_air_date']) as String?;
        final date = rawDate != null && isDateKey(rawDate) ? rawDate : null;
        final released = date != null && date.compareTo(today) <= 0;
        final votes = (item['vote_count'] as num?) ?? 0;
        final average = (item['vote_average'] as num?) ?? 0;
        var rating = votes > 0 && average > 0 ? 'TMDB ${average.toStringAsFixed(1)}' : '';
        if (omdbKey.isNotEmpty && released) {
          // A failed lookup for one title should not hide the whole list.
          String? imdb;
          try {
            imdb = await _imdbRating(kind, item['id'] as int, tmdbKey, omdbKey);
          } on KeyError {
            rethrow;
          } catch (_) {
            imdb = null;
          }
          if (imdb != null) rating = 'IMDb $imdb';
        }
        return Found(
          extId: 'tmdb:$kind:${item['id']}',
          kind: kind,
          title: (item['title'] ?? item['name'] ?? 'Untitled') as String,
          releaseDate: date,
          note: kind == 'series' && released
              ? 'Series'
              : released
              ? 'Released'
              : 'Premiere',
          rating: rating,
          poster: switch (item['poster_path']) {
            final String path when path.isNotEmpty => 'https://image.tmdb.org/t/p/w185$path',
            _ => null,
          },
        );
      }(),
  ]);
  return (items: found, more: more);
}

/// For a series already on air: the date and label of its next episode, if one is scheduled.
Future<({String date, String note})?> nextEpisode(String extId, String key) async {
  final show = await _tmdb('/tv/${extId.split(':')[2]}', key);
  final next = show['next_episode_to_air'] as Map<String, dynamic>?;
  final date = next?['air_date'] as String?;
  if (next == null || date == null) return null;
  return (date: date, note: 'Season ${next['season_number']} episode ${next['episode_number']}');
}
