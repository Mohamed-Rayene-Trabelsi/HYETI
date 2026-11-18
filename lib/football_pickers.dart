import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'football.dart';
import 'theme.dart';
import 'ui.dart';

/// The first-time setup: your country, then favourite clubs, then the big leagues. Every step can be skipped.
Future<void> openFootballSetup(BuildContext context) => showSheet(
  context,
  title: 'Your football',
  builder: (sheet) => _Setup(onDone: () => Navigator.pop(sheet)),
);

/// Changing one part of what is followed, from Settings. Each change is saved at once.
Future<void> openFootballEdit(BuildContext context, String part) => showSheet(
  context,
  title: switch (part) {
    'nation' => 'Your country',
    'clubs' => 'Favourite clubs',
    _ => 'Leagues',
  },
  builder: (sheet) => _Edit(part: part),
);

class _Setup extends StatefulWidget {
  const _Setup({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  int _step = 0;
  late FootballPrefs _draft = footballPrefs();

  Future<void> _next() async {
    if (_step < 2) return setState(() => _step++);
    await saveFootballPrefs(_draft.copyWith(setUp: true, off: false));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = switch (_step) {
      0 => _draft.nation != null,
      1 => _draft.clubs.isNotEmpty,
      _ => _draft.leagues.isNotEmpty,
    };
    return FormColumn(
      children: [
        T(
          'Step ${_step + 1} of 3 · ${['Your country', 'Favourite clubs', 'The big leagues'][_step]}',
          variant: TextVariant.label,
          dim: true,
        ),
        switch (_step) {
          0 => NationPicker(
            selected: _draft.nation,
            onPick: (t) => setState(() => _draft = _draft.copyWith(nation: () => _draft.nation == t ? null : t)),
          ),
          1 => ClubPicker(
            selected: _draft.clubs,
            onChanged: (clubs) => setState(() => _draft = _draft.copyWith(clubs: clubs)),
          ),
          _ => LeaguePicker(
            selected: _draft.leagues,
            onChanged: (leagues) => setState(() => _draft = _draft.copyWith(leagues: leagues)),
          ),
        },
        Row(
          spacing: Spacing.sm,
          children: [
            if (_step > 0)
              Expanded(
                child: AppButton('Back', kind: ButtonKind.soft, onPressed: () => setState(() => _step--)),
              ),
            Expanded(
              child: AppButton(
                _step == 2 ? 'Done' : (chosen ? 'Next' : 'Skip'),
                kind: chosen || _step == 2 ? ButtonKind.primary : ButtonKind.soft,
                onPressed: _next,
              ),
            ),
          ],
        ),
        const T('You can change all of this later in Settings.', variant: TextVariant.small, dim: true),
      ],
    );
  }
}

class _Edit extends StatefulWidget {
  const _Edit({required this.part});

  final String part;

  @override
  State<_Edit> createState() => _EditState();
}

class _EditState extends State<_Edit> {
  late FootballPrefs _prefs = footballPrefs();

  void _save(FootballPrefs next) {
    setState(() => _prefs = next.copyWith(setUp: true));
    saveFootballPrefs(_prefs);
  }

  @override
  Widget build(BuildContext context) => switch (widget.part) {
    'nation' => NationPicker(
      selected: _prefs.nation,
      onPick: (t) => _save(_prefs.copyWith(nation: () => _prefs.nation == t ? null : t)),
    ),
    'clubs' => ClubPicker(
      selected: _prefs.clubs,
      onChanged: (clubs) => _save(_prefs.copyWith(clubs: clubs)),
    ),
    _ => LeaguePicker(
      selected: _prefs.leagues,
      onChanged: (l) => _save(_prefs.copyWith(leagues: l)),
    ),
  };
}

/// Pick one national team. Tapping the chosen one again clears it.
class NationPicker extends StatelessWidget {
  const NationPicker({super.key, required this.selected, required this.onPick});

  final Team? selected;
  final ValueChanged<Team> onPick;

  @override
  Widget build(BuildContext context) => TeamSearch(
    nations: true,
    hint: 'Search your country',
    pinned: [?selected],
    isChosen: (t) => t == selected,
    onTap: onPick,
  );
}

/// Pick any number of clubs.
class ClubPicker extends StatelessWidget {
  const ClubPicker({super.key, required this.selected, required this.onChanged});

  final List<Team> selected;
  final ValueChanged<List<Team>> onChanged;

  @override
  Widget build(BuildContext context) => TeamSearch(
    nations: false,
    hint: 'Search clubs',
    pinned: selected,
    isChosen: selected.contains,
    onTap: (t) => onChanged(selected.contains(t) ? [...selected.where((c) => c != t)] : [...selected, t]),
  );
}

/// Tick any of the five big leagues.
class LeaguePicker extends StatelessWidget {
  const LeaguePicker({super.key, required this.selected, required this.onChanged});

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, MapEntry(key: id, value: name)) in topLeagues.entries.indexed)
          _ChoiceRow(
            divider: i > 0,
            label: name,
            chosen: selected.contains(id),
            onTap: () => onChanged([
              for (final l in topLeagues.keys)
                if (l == id ? !selected.contains(id) : selected.contains(l)) l,
            ]),
          ),
      ],
    );
  }
}

/// A search box for teams, with the ones already chosen listed first. The search runs as you type,
/// once the typing pauses, and only then is anything downloaded.
class TeamSearch extends StatefulWidget {
  const TeamSearch({
    super.key,
    required this.nations,
    required this.hint,
    required this.pinned,
    required this.isChosen,
    required this.onTap,
  });

  final bool nations;
  final String hint;

  /// Shown above the results, so what is chosen can be taken off without searching for it.
  final List<Team> pinned;
  final bool Function(Team) isChosen;
  final ValueChanged<Team> onTap;

  @override
  State<TeamSearch> createState() => _TeamSearchState();
}

class _TeamSearchState extends State<TeamSearch> {
  final _text = TextEditingController();
  Timer? _typing;
  int _request = 0;
  bool _loading = false;
  String _error = '';
  List<Team> _found = [];

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
    if (term.length < 2) {
      _request++;
      return setState(() {
        _found = [];
        _loading = false;
        _error = '';
      });
    }
    _typing = Timer(const Duration(milliseconds: 400), () => _search(term));
  }

  Future<void> _search(String term) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final found = await searchTeams(term, nations: widget.nations);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _found = found;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Could not search. Is the phone online?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = [...widget.pinned, ..._found.where((t) => !widget.pinned.contains(t))];
    final typed = _text.text.trim().length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        Field(
          controller: _text,
          icon: Icons.search,
          hint: widget.hint,
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Center(child: CircularProgressIndicator(color: c.accent)),
          ),
        if (_error.isNotEmpty) T(_error, dim: true),
        if (!_loading && _error.isEmpty && typed && _found.isEmpty)
          T(widget.nations ? 'No national team by that name.' : 'No club by that name.', dim: true),
        Column(
          children: [
            for (final (i, team) in rows.indexed)
              _ChoiceRow(
                divider: i > 0,
                label: team.name,
                sub: team.league,
                chosen: widget.isChosen(team),
                onTap: () => widget.onTap(team),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.divider,
    required this.label,
    this.sub = '',
    required this.chosen,
    required this.onTap,
  });

  final bool divider;
  final String label;
  final String sub;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: chosen,
      child: ListRow(
        divider: divider,
        onTap: () {
          tick();
          onTap();
        },
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(label, maxLines: 1),
                if (sub.isNotEmpty) T(sub, variant: TextVariant.small, dim: true, maxLines: 1),
              ],
            ),
          ),
          Icon(chosen ? Icons.check_circle : Icons.circle_outlined, size: 20, color: chosen ? c.accent : c.textDim),
        ],
      ),
    );
  }
}
