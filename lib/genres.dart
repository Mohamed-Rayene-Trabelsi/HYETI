import 'db.dart';

/// Genres, by one set of names for every source, so a filter or a taste means the same in Movies, Series and
/// Anime. TMDB and AniList each have their own lists; these maps translate them.

const _tmdbMovie = {
  28: ['Action'],
  12: ['Adventure'],
  16: ['Animation'],
  35: ['Comedy'],
  80: ['Crime'],
  99: ['Documentary'],
  18: ['Drama'],
  10751: ['Family'],
  14: ['Fantasy'],
  36: ['History'],
  27: ['Horror'],
  10402: ['Music'],
  9648: ['Mystery'],
  10749: ['Romance'],
  878: ['Sci-Fi'],
  53: ['Thriller'],
  10752: ['War'],
  37: ['Western'],
};

/// TMDB lumps some genres together for TV, so one of its ids can stand for two of ours.
const _tmdbTv = {
  10759: ['Action', 'Adventure'],
  16: ['Animation'],
  35: ['Comedy'],
  80: ['Crime'],
  99: ['Documentary'],
  18: ['Drama'],
  10751: ['Family'],
  10762: ['Kids'],
  9648: ['Mystery'],
  10764: ['Reality'],
  10765: ['Sci-Fi', 'Fantasy'],
  10768: ['War'],
  37: ['Western'],
};

/// AniList's genres, minus the adult ones, which are never shown.
const _anilist = {
  'Action': 'Action',
  'Adventure': 'Adventure',
  'Comedy': 'Comedy',
  'Drama': 'Drama',
  'Fantasy': 'Fantasy',
  'Horror': 'Horror',
  'Mahou Shoujo': 'Fantasy',
  'Mecha': 'Mecha',
  'Music': 'Music',
  'Mystery': 'Mystery',
  'Psychological': 'Psychological',
  'Romance': 'Romance',
  'Sci-Fi': 'Sci-Fi',
  'Slice of Life': 'Slice of Life',
  'Sports': 'Sports',
  'Supernatural': 'Supernatural',
  'Thriller': 'Thriller',
};

Map<int, List<String>> _tmdbMap(String kind) => kind == 'movie' ? _tmdbMovie : _tmdbTv;

/// The genres the filter offers for [kind] ('movie', 'series' or 'anime'), in alphabetical order.
List<String> genresFor(String kind) {
  final names = kind == 'anime' ? _anilist.values.toSet() : {for (final list in _tmdbMap(kind).values) ...list};
  return names.toList()..sort();
}

/// Our genre names for a TMDB title's `genre_ids` (or the ids of its `genres`).
List<String> tmdbGenres(String kind, Iterable<Object?> ids) {
  final map = _tmdbMap(kind);
  return {
    for (final id in ids)
      if (id is num) ...?map[id.toInt()],
  }.toList();
}

/// The TMDB genre id to ask for [genre], or null when TMDB has no such genre for [kind].
int? tmdbGenreId(String kind, String genre) {
  for (final MapEntry(:key, :value) in _tmdbMap(kind).entries) {
    if (value.contains(genre)) return key;
  }
  return null;
}

/// Our genre names for an AniList title's `genres`.
List<String> anilistGenres(Iterable<Object?> names) => {
  for (final n in names)
    if (_anilist[n] case final String g) g,
}.toList();

/// The AniList genre to ask for [genre], or null when AniList has none by that name.
String? anilistGenre(String genre) => _anilist.containsKey(genre) ? genre : null;

/// A stored comma list back into names. Null or empty is no genres.
List<String> parseGenres(Object? stored) => stored is String && stored.isNotEmpty
    ? stored.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList()
    : [];

/// Names to a comma list for storage; null when there are none, so "not known" and "none" look the same.
String? joinGenres(List<String> genres) => genres.isEmpty ? null : genres.join(',');

/* ---------- Taste: what the person likes, read from what they saved ---------- */

/// How much each genre is liked, and which titles to base recommendations on.
class Taste {
  const Taste({required this.weights, required this.saved, required this.seeds});

  /// Genre → weight. A title on the list counts once per genre; one finished, planned on the calendar or read
  /// far counts a little more.
  final Map<String, double> weights;

  /// Every `ext_id` on the watchlist, so recommendations skip what is already there.
  final Set<String> saved;

  /// Saved titles to find similar ones for, newest first: (ext_id, title).
  final List<(String, String)> seeds;

  bool get isEmpty => weights.isEmpty && seeds.isEmpty;

  /// The best-liked genres, most liked first.
  List<String> top([int n = 3]) {
    final sorted = weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(n)) e.key];
  }

  /// How well a title with [genres] fits, 0 when none of them is liked.
  double score(List<String> genres) => genres.fold(0.0, (sum, g) => sum + (weights[g] ?? 0));

  /// The liked genres among [genres], best liked first, for saying why a title is suggested.
  List<String> liked(List<String> genres) =>
      genres.where((g) => (weights[g] ?? 0) > 0).toList()..sort((a, b) => weights[b]!.compareTo(weights[a]!));
}

/// The taste read from the watchlist.
Future<Taste> loadTaste() async {
  final watched = await appDb.query(
    'SELECT ext_id, title, genres, event_id FROM watch_items WHERE kind != ? ORDER BY id DESC',
    ['match'],
  );
  final weights = <String, double>{};
  void add(Object? genres, double weight) {
    for (final g in parseGenres(genres)) {
      weights[g] = (weights[g] ?? 0) + weight;
    }
  }

  // Genres picked as favourites in the Watch setup count from the start, so suggestions work before anything
  // is saved; saved titles soon outweigh them.
  final picked = appDb.setting<Map>('watch_prefs', const {})['genres'];
  if (picked is List) add(picked.join(','), 2);
  for (final w in watched) {
    add(w['genres'], w['event_id'] != null ? 1.5 : 1);
  }
  final saved = {
    for (final row in watched)
      if (row['ext_id'] case final String id) id,
  };
  final seeds = [
    for (final w in watched)
      if (w['ext_id'] case final String id) (id, w['title'] as String),
  ];
  return Taste(weights: weights, saved: saved, seeds: seeds);
}
