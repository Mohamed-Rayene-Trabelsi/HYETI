import 'dart:convert';

import 'package:http/http.dart' as http;

import 'date.dart';
import 'db.dart';
import 'genres.dart';

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
    this.genres = const [],
    this.reason = '',
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

  /// Genre names from `lib/genres.dart`.
  final List<String> genres;

  /// Why a title is suggested, e.g. "Because you saved Dune"; empty outside "For you".
  final String reason;

  Found withReason(String reason) => Found(
    extId: extId,
    kind: kind,
    title: title,
    releaseDate: releaseDate,
    startMin: startMin,
    note: note,
    rating: rating,
    poster: poster,
    genres: genres,
    reason: reason,
  );
}

/// A service refused the key it was given.
class KeyError implements Exception {
  const KeyError(this.message);
  final String message;
}

/// One page of titles found online, and whether a further page exists.
typedef FoundPage = ({List<Found> items, bool more});

/// "Because you like Action and Comedy", from the liked genres of a suggested title.
String _likeReason(Taste taste, List<String> genres) {
  final liked = taste.liked(genres).take(2).toList();
  return liked.isEmpty ? '' : 'Because you like ${liked.join(' and ')}';
}

/// Puts suggestions best fit first: a title found from a saved one gets a head start, then liked genres decide.
/// Ties keep the source's order.
List<Found> rankForYou(Iterable<Found> found, Taste taste, {Set<String> similar = const {}}) {
  double fit(Found f) => taste.score(f.genres) + (similar.contains(f.extId) ? 3 : 0);
  final list = found.toList();
  final order = {for (final (i, f) in list.indexed) f.extId: i};
  return list..sort((a, b) {
    final byFit = fit(b).compareTo(fit(a));
    return byFit != 0 ? byFit : order[a.extId]!.compareTo(order[b.extId]!);
  });
}

/* ---------- Anime and manga: AniList, no key ---------- */

const _anilistFields = r'''
fragment fields on Media {
  id
  title { romaji english }
  averageScore
  status
  format
  episodes
  chapters
  countryOfOrigin
  genres
  isAdult
  nextAiringEpisode { airingAt episode }
  startDate { year month day }
  coverImage { medium }
}''';

const _anilistQuery =
    r'''
query ($type: MediaType, $search: String, $page: Int, $sort: [MediaSort], $status: [MediaStatus],
    $genres: [String], $exclude: [Int], $minScore: Int) {
  Page(page: $page, perPage: 20) {
    pageInfo { hasNextPage }
    media(type: $type, search: $search, sort: $sort, status_in: $status, genre_in: $genres, id_not_in: $exclude,
        averageScore_greater: $minScore, isAdult: false) {
      ...fields
    }
  }
}''' +
    _anilistFields;

/// What AniList's users recommend for each of the given anime.
const _anilistSimilarQuery =
    r'''
query ($ids: [Int]) {
  Page(perPage: 10) {
    media(id_in: $ids, type: ANIME) {
      title { romaji english }
      recommendations(sort: RATING_DESC, perPage: 8) {
        nodes { mediaRecommendation { ...fields } }
      }
    }
  }
}''' +
    _anilistFields;

const _anilistNextQuery = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) { nextAiringEpisode { airingAt episode } }
}''';

const _anilistGenresQuery = r'''
query ($id: Int) {
  Media(id: $id) { genres }
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

String _anilistTitle(Map<String, dynamic> m) =>
    ((m['title'] as Map<String, dynamic>?)?['english'] ?? m['title']?['romaji'] ?? 'Untitled') as String;

Found _animeFound(Map<String, dynamic> m) {
  final extId = 'anilist:${m['id']}';
  final poster = (m['coverImage'] as Map<String, dynamic>?)?['medium'] as String?;
  final title = _anilistTitle(m);
  final score = m['averageScore'] as num?;
  final rating = score != null && score > 0 ? 'AniList ${(score / 10).toStringAsFixed(1)}' : '';
  final genres = anilistGenres(m['genres'] as List? ?? const []);
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
      genres: genres,
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
    genres: genres,
    releaseDate: known ? toKey(DateTime(year, month, day)) : null,
    note: _animeNote(m, dated: known),
  );
}

FoundPage _animePage(Map<String, dynamic> data) {
  final result = data['Page'] as Map<String, dynamic>;
  final media = result['media'] as List;
  final more = (result['pageInfo'] as Map<String, dynamic>?)?['hasNextPage'] == true;
  return (items: [for (final m in media.cast<Map<String, dynamic>>()) _animeFound(m)], more: more);
}

/// Page [page] (from 1) of anime. With no [search]: trending shows that are airing or about to.
/// With one: the closest matches among all anime, finished ones included.
/// A [genre] keeps to that genre. A [taste] asks for suggestions instead (see [_animeForYou]).
Future<FoundPage> fetchAnime(String search, {int page = 1, String? genre, Taste? taste}) async {
  if (taste != null && search.isEmpty) return _animeForYou(taste, page: page, genre: genre);
  final asked = genre == null ? null : anilistGenre(genre);
  final data = await _anilist(_anilistQuery, {
    'type': 'ANIME',
    'page': page,
    'genres': ?(asked == null ? null : [asked]),
    if (search.isNotEmpty) ...{
      'search': search,
      'sort': ['SEARCH_MATCH', 'POPULARITY_DESC'],
    } else ...{
      'sort': ['TRENDING_DESC'],
      'status': ['RELEASING', 'NOT_YET_RELEASED'],
    },
  });
  return _animePage(data);
}

/// Anime picked for the person: what AniList's users recommend for anime they saved, then well-rated anime in
/// the genre they like best. Nothing already on their lists.
Future<FoundPage> _animeForYou(Taste taste, {required int page, String? genre}) async {
  int? anilistId(String extId) => extId.startsWith('anilist:') ? int.tryParse(extId.substring(8)) : null;
  final exclude = taste.saved.map(anilistId).nonNulls.toList();
  final asked = genre == null ? null : anilistGenre(genre);
  final genres = asked != null ? [asked] : taste.top(1).map(anilistGenre).nonNulls.toList();

  final similar = <Found>[];
  final similarIds = <String>{};
  final seeds = taste.seeds.map((s) => anilistId(s.$1)).nonNulls.take(5).toList();
  if (page == 1 && seeds.isNotEmpty) {
    final data = await _anilist(_anilistSimilarQuery, {'ids': seeds});
    for (final m in ((data['Page'] as Map<String, dynamic>)['media'] as List).cast<Map<String, dynamic>>()) {
      final from = _anilistTitle(m);
      final nodes = (m['recommendations'] as Map<String, dynamic>?)?['nodes'] as List? ?? const [];
      for (final node in nodes.cast<Map<String, dynamic>>()) {
        final rec = node['mediaRecommendation'] as Map<String, dynamic>?;
        if (rec == null || rec['isAdult'] == true || exclude.contains(rec['id'])) continue;
        final f = _animeFound(rec);
        if (genre != null && !f.genres.contains(genre)) continue;
        if (similarIds.add(f.extId)) similar.add(f.withReason('Because you saved $from'));
      }
    }
  }

  // With no liked genre yet, the most popular well-rated anime stand in.
  final byGenre = _animePage(
    await _anilist(_anilistQuery, {
      'type': 'ANIME',
      'page': page,
      'sort': ['POPULARITY_DESC'],
      'minScore': 70,
      if (genres.isNotEmpty) 'genres': genres,
      if (exclude.isNotEmpty) 'exclude': exclude,
    }),
  );
  final rest = [
    for (final f in byGenre.items)
      if (!similarIds.contains(f.extId)) f.withReason(_likeReason(taste, f.genres)),
  ];
  return (items: rankForYou([...similar, ...rest], taste, similar: similarIds), more: byGenre.more);
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

/// Hot (trending this week), upcoming or suggested movies / series, each with a rating.
/// [mode] is 'hot', 'upcoming' or 'foryou' (which needs [taste]); a non-empty [search] overrides it.
/// A [genre] keeps to that genre. [page] counts from 1.
Future<FoundPage> fetchTitles(
  String kind,
  String mode,
  String search, {
  required String tmdbKey,
  required String omdbKey,
  int page = 1,
  String? genre,
  Taste? taste,
}) async {
  final type = _tmdbType(kind);
  final today = todayKey();
  final at = {'page': '$page'};
  final genreId = genre == null ? null : tmdbGenreId(kind, genre);
  final similar = <Map<String, dynamic>>[];
  final similarFrom = <int, String>{};
  final Map<String, dynamic> result;
  if (search.isNotEmpty) {
    // TMDB's search takes no genre; the results are sifted below instead.
    result = await _tmdb('/search/$type', tmdbKey, {'query': search, ...at});
  } else if (mode == 'foryou' && taste != null) {
    // What TMDB suggests for the newest titles saved, then popular, well-voted titles in the liked genres.
    if (page == 1) {
      final seeds = [
        for (final (id, title) in taste.seeds)
          if (id.startsWith('tmdb:$kind:')) (int.tryParse(id.split(':')[2]), title),
      ].where((s) => s.$1 != null).take(3);
      final answers = await Future.wait([
        for (final (id, title) in seeds)
          _tmdb(
            '/$type/$id/recommendations',
            tmdbKey,
          ).then<(String, Map<String, dynamic>?)>((r) => (title, r), onError: (_) => (title, null)),
      ]);
      for (final (title, r) in answers) {
        for (final item in ((r?['results'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          final id = item['id'] as int;
          if (similarFrom.containsKey(id)) continue;
          similarFrom[id] = title;
          similar.add(item);
        }
      }
    }
    final liked = genreId != null ? [genreId] : {for (final g in taste.top()) ?tmdbGenreId(kind, g)}.toList();
    result = await _tmdb('/discover/$type', tmdbKey, {
      'sort_by': 'popularity.desc',
      'vote_count.gte': '150',
      // Any of the liked genres, not all of them.
      if (liked.isNotEmpty) 'with_genres': liked.join('|'),
      ...at,
    });
  } else if (mode == 'hot' && genreId == null) {
    result = await _tmdb('/trending/$type/week', tmdbKey, at);
  } else if (mode == 'hot') {
    // Trending takes no genre either; the most popular titles of the genre come closest.
    result = await _tmdb('/discover/$type', tmdbKey, {'sort_by': 'popularity.desc', 'with_genres': '$genreId', ...at});
  } else {
    // Popular titles whose first release falls in the next three months.
    final dateField = kind == 'movie' ? 'primary_release_date' : 'first_air_date';
    result = await _tmdb('/discover/$type', tmdbKey, {
      'sort_by': 'popularity.desc',
      '$dateField.gte': today,
      '$dateField.lte': addDays(today, 90),
      'with_genres': ?genreId?.toString(),
      ...at,
    });
  }

  final more = page < ((result['total_pages'] as num?) ?? 1);
  final seen = <int>{};
  final items = [
    for (final item in [...similar, ...(result['results'] as List).cast<Map<String, dynamic>>()])
      if (seen.add(item['id'] as int))
        if (taste == null || !taste.saved.contains('tmdb:$kind:${item['id']}'))
          if (genre == null || tmdbGenres(kind, item['genre_ids'] as List? ?? const []).contains(genre)) item,
  ];
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
        final genres = tmdbGenres(kind, item['genre_ids'] as List? ?? const []);
        final from = similarFrom[item['id']];
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
          genres: genres,
          reason: taste == null
              ? ''
              : from != null
              ? 'Because you saved $from'
              : _likeReason(taste, genres),
          poster: switch (item['poster_path']) {
            final String path when path.isNotEmpty => 'https://image.tmdb.org/t/p/w185$path',
            _ => null,
          },
        );
      }(),
  ]);
  if (taste == null) return (items: found, more: more);
  final similarIds = {for (final id in similarFrom.keys) 'tmdb:$kind:$id'};
  return (items: rankForYou(found, taste, similar: similarIds), more: more);
}

/// For a series already on air: the date and label of its next episode, if one is scheduled.
Future<({String date, String note})?> nextEpisode(String extId, String key) async {
  final show = await _tmdb('/tv/${extId.split(':')[2]}', key);
  final next = show['next_episode_to_air'] as Map<String, dynamic>?;
  final date = next?['air_date'] as String?;
  if (next == null || date == null) return null;
  return (date: date, note: 'Season ${next['season_number']} episode ${next['episode_number']}');
}

/// The genres of a saved title, looked up by its `ext_id`, for titles saved before genres were kept.
/// Null when it cannot be looked up (no key, or not from AniList or TMDB).
Future<List<String>?> fetchGenres(String extId, String tmdbKey) async {
  final parts = extId.split(':');
  if (parts.first == 'anilist') {
    final data = await _anilist(_anilistGenresQuery, {'id': int.parse(parts[1])});
    return anilistGenres((data['Media'] as Map<String, dynamic>?)?['genres'] as List? ?? const []);
  }
  if (parts.first == 'tmdb' && parts.length == 3 && tmdbKey.isNotEmpty) {
    final kind = parts[1];
    final details = await _tmdb('/${_tmdbType(kind)}/${parts[2]}', tmdbKey);
    return tmdbGenres(kind, [for (final g in (details['genres'] as List? ?? const [])) (g as Map)['id']]);
  }
  return null;
}
