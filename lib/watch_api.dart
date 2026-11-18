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

/* ---------- Football: ESPN's public scoreboard, no key ---------- */

/// The competitions offered: ESPN's name for each, and the name shown.
const footballLeagues = {
  'uefa.champions': 'Champions League',
  'eng.1': 'Premier League',
  'esp.1': 'La Liga',
  'ita.1': 'Serie A',
  'ger.1': 'Bundesliga',
  'fra.1': 'Ligue 1',
  'fifa.world': 'World Cup',
  'uefa.euro': 'Euros',
};

/// How far ahead football looks: this month and the ones after it, one month per page.
const footballMonths = 6;

/// A country whose football can be followed: its national team, its clubs in continental cups,
/// and its own leagues and cups where ESPN carries them.
class FootballCountry {
  const FootballCountry(this.name, this.confederation, {this.teamName, this.leagues = const []});

  final String name;

  /// 'uefa', 'caf', 'afc', 'conmebol', 'concacaf' or 'ofc'.
  final String confederation;

  /// ESPN's own competitions for the country, such as 'eng.1'.
  final List<String> leagues;

  /// ESPN's name for the national team, when it is not the country's name.
  final String? teamName;

  /// The national team as ESPN names it.
  String get team => teamName ?? name;
}

/// Every country offered. Tunisia, like most, has no league of its own on ESPN; its national team and
/// its clubs in the African cups still show.
const footballCountries = [
  FootballCountry('Algeria', 'caf'),
  FootballCountry('Argentina', 'conmebol', leagues: ['arg.1', 'arg.copa']),
  FootballCountry('Australia', 'afc', leagues: ['aus.1']),
  FootballCountry('Austria', 'uefa', leagues: ['aut.1']),
  FootballCountry('Bahrain', 'afc'),
  FootballCountry('Bangladesh', 'afc'),
  FootballCountry('Belgium', 'uefa', leagues: ['bel.1']),
  FootballCountry('Brazil', 'conmebol', leagues: ['bra.1', 'bra.copa_do_brazil']),
  FootballCountry('Bulgaria', 'uefa'),
  FootballCountry('Cameroon', 'caf'),
  FootballCountry('Canada', 'concacaf'),
  FootballCountry('Chile', 'conmebol', leagues: ['chi.1']),
  FootballCountry('China', 'afc', leagues: ['chn.1']),
  FootballCountry('Colombia', 'conmebol', leagues: ['col.1']),
  FootballCountry('Croatia', 'uefa'),
  FootballCountry('Cyprus', 'uefa'),
  FootballCountry('Czechia', 'uefa'),
  FootballCountry('Denmark', 'uefa', leagues: ['den.1']),
  FootballCountry('Egypt', 'caf'),
  FootballCountry('England', 'uefa', leagues: ['eng.1', 'eng.2', 'eng.fa', 'eng.league_cup']),
  FootballCountry('Estonia', 'uefa'),
  FootballCountry('Ethiopia', 'caf'),
  FootballCountry('Finland', 'uefa'),
  FootballCountry('France', 'uefa', leagues: ['fra.1', 'fra.2', 'fra.coupe_de_france']),
  FootballCountry('Germany', 'uefa', leagues: ['ger.1', 'ger.2', 'ger.dfb_pokal']),
  FootballCountry('Ghana', 'caf'),
  FootballCountry('Greece', 'uefa', leagues: ['gre.1']),
  FootballCountry('Hong Kong', 'afc'),
  FootballCountry('Hungary', 'uefa'),
  FootballCountry('Iceland', 'uefa'),
  FootballCountry('India', 'afc', leagues: ['ind.1']),
  FootballCountry('Indonesia', 'afc'),
  FootballCountry('Iraq', 'afc'),
  FootballCountry('Ireland', 'uefa', teamName: 'Republic of Ireland'),
  FootballCountry('Israel', 'uefa'),
  FootballCountry('Italy', 'uefa', leagues: ['ita.1', 'ita.2', 'ita.coppa_italia']),
  FootballCountry('Ivory Coast', 'caf'),
  FootballCountry('Japan', 'afc', leagues: ['jpn.1']),
  FootballCountry('Jordan', 'afc'),
  FootballCountry('Kenya', 'caf'),
  FootballCountry('Kuwait', 'afc'),
  FootballCountry('Latvia', 'uefa'),
  FootballCountry('Lebanon', 'afc'),
  FootballCountry('Libya', 'caf'),
  FootballCountry('Lithuania', 'uefa'),
  FootballCountry('Luxembourg', 'uefa'),
  FootballCountry('Malaysia', 'afc'),
  FootballCountry('Malta', 'uefa'),
  FootballCountry('Mauritania', 'caf'),
  FootballCountry('Mexico', 'concacaf', leagues: ['mex.1']),
  FootballCountry('Morocco', 'caf'),
  FootballCountry('Netherlands', 'uefa', leagues: ['ned.1', 'ned.cup']),
  FootballCountry('New Zealand', 'ofc'),
  FootballCountry('Nigeria', 'caf'),
  FootballCountry('Northern Ireland', 'uefa'),
  FootballCountry('Norway', 'uefa', leagues: ['nor.1']),
  FootballCountry('Oman', 'afc'),
  FootballCountry('Pakistan', 'afc'),
  FootballCountry('Palestine', 'afc'),
  FootballCountry('Peru', 'conmebol', leagues: ['per.1']),
  FootballCountry('Philippines', 'afc'),
  FootballCountry('Poland', 'uefa'),
  FootballCountry('Portugal', 'uefa', leagues: ['por.1', 'por.taca.portugal']),
  FootballCountry('Qatar', 'afc'),
  FootballCountry('Romania', 'uefa'),
  FootballCountry('Russia', 'uefa', leagues: ['rus.1']),
  FootballCountry('Saudi Arabia', 'afc', leagues: ['ksa.1', 'ksa.kings.cup']),
  FootballCountry('Scotland', 'uefa', leagues: ['sco.1', 'sco.tennents']),
  FootballCountry('Senegal', 'caf'),
  FootballCountry('Serbia', 'uefa'),
  FootballCountry('Singapore', 'afc'),
  FootballCountry('Slovakia', 'uefa'),
  FootballCountry('Slovenia', 'uefa'),
  FootballCountry('South Africa', 'caf', leagues: ['rsa.1']),
  FootballCountry('South Korea', 'afc'),
  FootballCountry('Spain', 'uefa', leagues: ['esp.1', 'esp.2', 'esp.copa_del_rey']),
  FootballCountry('Sri Lanka', 'afc'),
  FootballCountry('Sudan', 'caf'),
  FootballCountry('Sweden', 'uefa', leagues: ['swe.1']),
  FootballCountry('Switzerland', 'uefa'),
  FootballCountry('Syria', 'afc'),
  FootballCountry('Taiwan', 'afc', teamName: 'Chinese Taipei'),
  FootballCountry('Thailand', 'afc'),
  FootballCountry('Tunisia', 'caf'),
  FootballCountry('Turkey', 'uefa', teamName: 'Türkiye', leagues: ['tur.1']),
  FootballCountry('Ukraine', 'uefa'),
  FootballCountry('United Arab Emirates', 'afc'),
  FootballCountry('United States', 'concacaf', leagues: ['usa.1', 'usa.open']),
  FootballCountry('Vietnam', 'afc'),
  FootballCountry('Wales', 'uefa'),
  FootballCountry('Yemen', 'afc'),
];

FootballCountry? footballCountry(String name) => footballCountries.where((c) => c.name == name).firstOrNull;

/// Competitions between national teams: worldwide, and each confederation's own.
const _worldTeamCups = ['fifa.friendly', 'fifa.world'];
const _teamCups = {
  'uefa': ['fifa.worldq.uefa', 'uefa.nations', 'uefa.euro', 'uefa.euroq'],
  'caf': ['fifa.worldq.caf', 'caf.nations', 'caf.nations_qual'],
  'afc': ['fifa.worldq.afc', 'afc.asian.cup', 'global.gulf_cup'],
  'conmebol': ['fifa.worldq.conmebol', 'conmebol.america'],
  'concacaf': ['fifa.worldq.concacaf', 'concacaf.nations.league', 'concacaf.gold'],
  'ofc': ['fifa.worldq.ofc'],
};

/// Each confederation's cups between clubs.
const _clubCups = {
  'uefa': ['uefa.champions', 'uefa.europa', 'uefa.europa.conf'],
  'caf': ['caf.champions', 'caf.confed'],
  'afc': ['afc.champions'],
  'conmebol': ['conmebol.libertadores', 'conmebol.sudamericana'],
  'concacaf': ['concacaf.champions'],
  'ofc': <String>[],
};

/// One match, with what is needed to tell whose it is.
typedef _Match = ({DateTime kickOff, Found found, String home, String away, String venueCountry, bool played});

/// Picks a country's matches out of one competition's upcoming [month]. [around] is that month and the ones
/// either side, played matches included, for picks that need it (see [_clubsOf]).
typedef _Pick = Iterable<_Match> Function(List<_Match> month, List<_Match> around);

/// A competition to ask for, what to keep from it, and whether the picks need the months around.
typedef _Ask = ({List<_Pick> picks, bool around});

Iterable<_Match> _all(List<_Match> month, List<_Match> around) => month;

/// The matches [country]'s national team plays.
_Pick _teamOf(FootballCountry country) =>
    (month, _) => month.where((m) => m.home == country.team || m.away == country.team);

/// The matches [country]'s clubs play. ESPN does not say where a club is from, so a club counts as
/// the country's when it plays a home match there. Cup ties are home and away a few weeks apart, so the
/// months either side are looked at too: an away leg still shows when the home leg is in the next month.
_Pick _clubsOf(FootballCountry country) => (month, around) {
  final clubs = {
    for (final m in [...month, ...around])
      if (m.venueCountry == country.name || m.venueCountry == country.team) m.home,
  };
  return month.where((m) => clubs.contains(m.home) || clubs.contains(m.away));
};

/// The competitions to ask for and what to keep from each, for [filter]: '' for the competitions
/// offered plus the [countries] followed, a competition such as 'eng.1', or 'country:Tunisia'.
Map<String, _Ask> _plan(String filter, List<String> countries) {
  final plan = <String, _Ask>{};
  void add(String league, _Pick pick, {bool around = false}) {
    final ask = plan[league];
    plan[league] = (picks: [...?ask?.picks, pick], around: around || (ask?.around ?? false));
  }

  void follow(FootballCountry country) {
    for (final l in country.leagues) {
      add(l, _all);
    }
    for (final l in [..._worldTeamCups, ...?_teamCups[country.confederation]]) {
      add(l, _teamOf(country));
    }
    for (final l in _clubCups[country.confederation] ?? const <String>[]) {
      add(l, _clubsOf(country), around: true);
    }
  }

  if (filter.startsWith('country:')) {
    final country = footballCountry(filter.substring(8));
    if (country != null) follow(country);
  } else if (filter.isNotEmpty) {
    add(filter, _all);
  } else {
    for (final l in footballLeagues.keys) {
      add(l, _all);
    }
    for (final name in countries) {
      final country = footballCountry(name);
      if (country != null) follow(country);
    }
  }
  return plan;
}

/// The matches of one competition in one month ('YYYYMM').
Future<List<_Match>> _monthMatches(String league, String month) async {
  final res = await httpClient
      .get(
        // A whole month in one answer; without a limit ESPN stops at 100 matches.
        Uri.https('site.api.espn.com', '/apis/site/v2/sports/soccer/$league/scoreboard', {
          'dates': month,
          'limit': '1000',
        }),
        headers: const {'Accept': 'application/json'},
      )
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('ESPN answered ${res.statusCode}');
  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final competition =
      footballLeagues[league] ??
      ((body['leagues'] as List?)?.cast<Map<String, dynamic>>().firstOrNull?['name'] as String?) ??
      'Football';
  final events = body['events'] as List? ?? const [];
  final matches = <_Match>[];
  for (final event in events.cast<Map<String, dynamic>>()) {
    final game = (event['competitions'] as List?)?.cast<Map<String, dynamic>>().firstOrNull;
    final kickOff = DateTime.tryParse((event['date'] as String?) ?? '')?.toLocal();
    if (game == null || kickOff == null) continue;
    final status = (game['status'] ?? event['status']) as Map<String, dynamic>?;
    Map<String, dynamic>? team(String side) => (game['competitors'] as List?)
        ?.cast<Map<String, dynamic>>()
        .where((c) => c['homeAway'] == side)
        .map((c) => c['team'] as Map<String, dynamic>?)
        .firstOrNull;
    final home = team('home'), away = team('away');
    if (home == null || away == null) continue;
    final homeName = home['displayName'] as String? ?? 'Home', awayName = away['displayName'] as String? ?? 'Away';
    final min = kickOff.hour * 60 + kickOff.minute;
    matches.add((
      kickOff: kickOff,
      home: homeName,
      away: awayName,
      played: (status?['type'] as Map<String, dynamic>?)?['state'] == 'post',
      venueCountry:
          ((game['venue'] as Map<String, dynamic>?)?['address'] as Map<String, dynamic>?)?['country'] as String? ?? '',
      found: Found(
        extId: 'espn:${event['id']}',
        kind: 'match',
        title: '$homeName vs $awayName',
        releaseDate: toKey(kickOff),
        startMin: min,
        note: '$competition · ${formatTime(min)}',
        rating: '',
        poster: home['logo'] as String?,
      ),
    ));
  }
  return matches;
}

/// Upcoming football matches for [filter] (see [_plan]), soonest first. Page 1 is the rest of this month,
/// each later page the month after; there are [footballMonths] pages.
Future<FoundPage> fetchMatches(String filter, {int page = 1, List<String> countries = const [], DateTime? now}) async {
  final today = now ?? DateTime.now();
  String monthKey(int ahead) {
    final d = DateTime(today.year, today.month + page - 1 + ahead);
    return '${d.year}${d.month.toString().padLeft(2, '0')}';
  }

  // The months either side only help to place clubs; a failure there leaves them out.
  Future<List<_Match>> quietly(String league, String month) =>
      _monthMatches(league, month).catchError((_) => <_Match>[]);

  final plan = _plan(filter, countries);
  var failed = 0;
  final picked = await Future.wait([
    for (final MapEntry(key: league, value: ask) in plan.entries)
      () async {
        try {
          final [month, before, after] = await Future.wait([
            _monthMatches(league, monthKey(0)),
            if (ask.around) ...[
              quietly(league, monthKey(-1)),
              quietly(league, monthKey(1)),
            ] else ...[
              Future.value(<_Match>[]),
              Future.value(<_Match>[]),
            ],
          ]);
          final upcoming = [
            for (final m in month)
              if (!m.played) m,
          ];
          return [
            for (final pick in ask.picks) ...pick(upcoming, [...month, ...before, ...after]),
          ];
        } catch (_) {
          // One competition failing should not hide the others.
          failed++;
          return <_Match>[];
        }
      }(),
  ]);
  if (plan.isNotEmpty && failed == plan.length) throw Exception('No football fixtures could be loaded');
  final seen = <String>{};
  final matches = [
    for (final m in picked.expand((p) => p))
      if (seen.add(m.found.extId)) m,
  ]..sort((a, b) => a.kickOff.compareTo(b.kickOff));
  return (items: [for (final m in matches) m.found], more: page < footballMonths);
}

/// For a series already on air: the date and label of its next episode, if one is scheduled.
Future<({String date, String note})?> nextEpisode(String extId, String key) async {
  final show = await _tmdb('/tv/${extId.split(':')[2]}', key);
  final next = show['next_episode_to_air'] as Map<String, dynamic>?;
  final date = next?['air_date'] as String?;
  if (next == null || date == null) return null;
  return (date: date, note: 'Season ${next['season_number']} episode ${next['episode_number']}');
}
