import 'package:material_ui/material_ui.dart';

import 'db.dart';
import 'football.dart';
import 'football_pickers.dart';
import 'genres.dart';
import 'theme.dart';
import 'ui.dart';

/// What the person watches and reads, asked the first time Watch opens and changed in Settings.
/// Football is part of the choice on screen, but is kept where it always was: `off` in the football settings.

/// The kinds the setup offers, in display order: id → (label, what it brings, icon).
const watchKinds = {
  'movie': ('Movies', 'Hot and upcoming films', Icons.movie_outlined),
  'series': ('Series', 'TV shows and their next episodes', Icons.tv),
  'anime': ('Anime', 'What is airing, from AniList', Icons.auto_awesome),
  'match': ('Football', 'Matches of your country, clubs and leagues', Icons.sports_soccer),
};

class WatchPrefs {
  const WatchPrefs({required this.setUp, required this.kinds, required this.genres});

  /// Until the setup is done or skipped, the Watch tab asks.
  final bool setUp;

  /// Ids from [watchKinds] that are shown, 'match' included.
  final Set<String> kinds;

  /// Genres picked as liked, which "For you" counts on before anything is saved.
  final List<String> genres;

  bool shows(String kind) => kinds.contains(kind);
}

/// Every genre any part of Watch knows, for picking favourites.
List<String> allGenres() => {...genresFor('movie'), ...genresFor('series'), ...genresFor('anime')}.toList()..sort();

WatchPrefs watchPrefs() {
  final saved = appDb.setting<Map>('watch_prefs', const {});
  final kinds = saved['kinds'] is List
      ? {for (final k in saved['kinds'] as List) k as String}
      : {'movie', 'series', 'anime'};
  // Manga was a kind until 1.5.0; a choice saved before then may still name it.
  kinds.removeAll(const ['match', 'manga']);
  if (!footballPrefs().off) kinds.add('match');
  return WatchPrefs(
    setUp: saved['setUp'] == true,
    kinds: kinds,
    genres: [for (final g in (saved['genres'] as List? ?? const [])) g as String],
  );
}

/// Saves the choice. Turning football on or off goes to the football settings, so the two never disagree.
Future<void> saveWatchPrefs({bool? setUp, Set<String>? kinds, List<String>? genres}) async {
  final now = watchPrefs();
  final next = kinds ?? now.kinds;
  await appDb.setSetting('watch_prefs', {
    'setUp': setUp ?? now.setUp,
    'kinds': [
      for (final k in watchKinds.keys)
        if (k != 'match' && next.contains(k)) k,
    ],
    'genres': genres ?? now.genres,
  });
  final football = footballPrefs();
  if (football.off == next.contains('match')) {
    // Turned on here, football still asks for a country and clubs on its own tab.
    await saveFootballPrefs(football.copyWith(off: !next.contains('match')));
  }
}

/// A tappable tile per kind, ticked when chosen.
class WatchKindsPicker extends StatelessWidget {
  const WatchKindsPicker({super.key, required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        for (final MapEntry(key: id, value: (label, hint, icon)) in watchKinds.entries)
          () {
            final on = selected.contains(id);
            final radius = BorderRadius.circular(Radii.md);
            return Semantics(
              button: true,
              selected: on,
              label: label,
              excludeSemantics: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: on ? c.accent.withValues(alpha: 0.12) : c.surfaceAlt,
                  borderRadius: radius,
                  border: Border.all(color: on ? c.accent : c.border, width: on ? 1.5 : 0.5),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: () {
                      tick();
                      onChanged(on ? ({...selected}..remove(id)) : {...selected, id});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                      child: Row(
                        spacing: Spacing.md,
                        children: [
                          Icon(icon, size: 22, color: on ? c.accent : c.textDim),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                T(label, variant: TextVariant.label, maxLines: 1),
                                T(hint, variant: TextVariant.small, dim: true, maxLines: 2),
                              ],
                            ),
                          ),
                          Icon(
                            on ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 22,
                            color: on ? c.accent : c.textDim,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// Genre chips to pick favourites from.
class FavouriteGenresPicker extends StatelessWidget {
  const FavouriteGenresPicker({super.key, required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final g in allGenres())
          AppChip(
            g,
            icon: selected.contains(g) ? Icons.favorite : null,
            selected: selected.contains(g),
            onPressed: () => onChanged(selected.contains(g) ? ([...selected]..remove(g)) : [...selected, g]),
          ),
      ],
    );
  }
}

/// The first-time setup on the Watch tab: what is watched, then which genres are liked.
class WatchSetup extends StatefulWidget {
  const WatchSetup({super.key});

  @override
  State<WatchSetup> createState() => _WatchSetupState();
}

class _WatchSetupState extends State<WatchSetup> {
  int _step = 0;
  late Set<String> _kinds = {...watchPrefs().kinds};
  late List<String> _genres = [...watchPrefs().genres];

  Future<void> _finish({bool everything = false}) async {
    final kinds = everything ? watchKinds.keys.toSet() : _kinds;
    await saveWatchPrefs(setUp: true, kinds: kinds, genres: _genres);
    // Football has its own few questions; ask them now rather than on a later visit.
    if (mounted && kinds.contains('match') && !footballPrefs().setUp) await openFootballSetup(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      spacing: Spacing.md,
      children: [
        Row(
          spacing: Spacing.md,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_step == 0 ? Icons.live_tv_outlined : Icons.favorite_outline, color: c.accent),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T('Step ${_step + 1} of 2', variant: TextVariant.small, dim: true),
                  T(_step == 0 ? 'What are you into?' : 'Which genres do you enjoy?', variant: TextVariant.heading),
                ],
              ),
            ),
          ],
        ),
        T(
          _step == 0
              ? 'Pick what you watch or read. Only those show up here.'
              : 'Pick a few. Suggestions under “For you” start from them, then learn from what you save.',
          dim: true,
        ),
        if (_step == 0)
          WatchKindsPicker(selected: _kinds, onChanged: (k) => setState(() => _kinds = k))
        else
          FavouriteGenresPicker(selected: _genres, onChanged: (g) => setState(() => _genres = g)),
        Row(
          spacing: Spacing.sm,
          children: [
            if (_step > 0)
              Expanded(
                child: AppButton('Back', kind: ButtonKind.soft, onPressed: () => setState(() => _step = 0)),
              ),
            Expanded(
              child: AppButton(
                _step == 0 ? 'Next' : (_genres.isEmpty ? 'Skip' : 'Done'),
                kind: _step == 1 && _genres.isEmpty ? ButtonKind.soft : ButtonKind.primary,
                onPressed: _step == 0 && _kinds.isEmpty
                    ? null
                    : () => _step == 0 ? setState(() => _step = 1) : _finish(),
              ),
            ),
          ],
        ),
        if (_step == 0 && _kinds.isEmpty)
          const T('Pick at least one.', variant: TextVariant.small, dim: true, align: TextAlign.center),
        if (_step == 0)
          AppButton(
            'Skip, show me everything',
            kind: ButtonKind.plain,
            small: true,
            onPressed: () => _finish(everything: true),
          ),
        const T(
          'You can change this any time in Settings, under Watch.',
          variant: TextVariant.small,
          dim: true,
          align: TextAlign.center,
        ),
      ],
    );
  }
}
