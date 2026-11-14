import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../body_map.dart';
import '../date.dart';
import '../db.dart';
import '../muscles.dart';
import '../pickers.dart';
import '../theme.dart';
import '../ui.dart';
import 'nutrition.dart';

class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  String _tab = 'gym';
  String _muscle = 'Chest';

  @override
  Widget build(BuildContext context) {
    final gym = _tab == 'gym';
    return Screen(
      title: 'Body',
      subtitle: formatDay(todayKey()),
      fabLabel: gym ? 'Log set' : 'Log food',
      onFab: gym ? () => openSetSheet(context, _muscle, '') : () => openFoodSheet(context),
      children: [
        Segmented<String>(
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          options: const {'gym': 'Gym', 'food': 'Nutrition'},
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: gym
              ? Gym(key: const ValueKey('gym'), muscle: _muscle, onMuscle: (m) => setState(() => _muscle = m))
              : const Nutrition(key: ValueKey('food')),
        ),
      ],
    );
  }
}

void openSetSheet(BuildContext context, String muscle, String exercise) {
  showSheet(
    context,
    title: 'Log a set',
    builder: (_) => _SetForm(initialMuscle: muscle, initialExercise: exercise),
  );
}

class Gym extends StatefulWidget {
  const Gym({super.key, required this.muscle, required this.onMuscle});

  /// The muscle picked on the map; owned by the screen so "Log set" can start from it.
  final String muscle;
  final ValueChanged<String> onMuscle;

  @override
  State<Gym> createState() => _GymState();
}

class _GymState extends State<Gym> with Live {
  String _side = 'front';
  String get _muscle => widget.muscle;

  /// The exercise whose form tip is open, if any.
  String? _tipFor;
  bool _allProgress = false;

  List<Rec> _lastTrained = [];
  List<Rec> _todaySets = [];
  List<Rec> _tops = [];

  @override
  Future<void> load() async {
    final last = await appDb.query('SELECT muscle, MAX(date) AS last FROM workout_sets GROUP BY muscle');
    final sets = await appDb.query('SELECT * FROM workout_sets WHERE date = ? ORDER BY id', [todayKey()]);
    final tops = await appDb.query(
      'SELECT exercise, date, MAX(weight) AS top FROM workout_sets GROUP BY exercise, date ORDER BY date',
    );
    _lastTrained = last;
    _todaySets = sets;
    _tops = tops;
  }

  void _openSetForm(String exercise) => openSetSheet(context, _muscle, exercise);

  void _openMembership() {
    showSheet(
      context,
      title: 'Gym membership',
      builder: (sheet) => _MembershipForm(
        membership: appDb.setting<Map<String, Object?>?>('membership', null),
        onSave: (m) async {
          await appDb.setSetting('membership', m);
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  /// Picks a muscle and turns the figure round if it is on the other side.
  void _pick(String muscle) {
    if (!muscleOnSide(muscle, _side)) setState(() => _side = _side == 'front' ? 'back' : 'front');
    widget.onMuscle(muscle);
  }

  static String _restLabel(int? days) => switch (days) {
    null => 'Not trained yet',
    0 => 'Trained today',
    1 => 'Trained yesterday',
    _ => 'Trained $days days ago',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final unit = appDb.setting('weight_unit', 'kg');

    // Longest-rested muscles first; never-trained ones lead.
    final lastByMuscle = {for (final r in _lastTrained) r['muscle'] as String: r['last'] as String};
    final rest = [
      for (final m in muscles) (muscle: m, days: lastByMuscle[m] == null ? null : daysBetween(lastByMuscle[m]!, today)),
    ]..sort((a, b) => (b.days ?? 9999) - (a.days ?? 9999));
    final upNext = rest.where((r) => r.days == null || r.days! >= 2).take(3).toList();
    // Amber marks muscles that have been trained before and then left for five days or more.
    final stale = _lastTrained.isEmpty
        ? <String>[]
        : [
            for (final r in rest)
              if (r.days != null && r.days! >= 5) r.muscle,
          ];
    final selectedDays = rest.firstWhere((r) => r.muscle == _muscle).days;

    final todayByExercise = <String, List<Rec>>{};
    for (final s in _todaySets) {
      (todayByExercise[s['exercise'] as String] ??= []).add(s);
    }

    final progress = <String, List<double>>{};
    for (final t in _tops) {
      (progress[t['exercise'] as String] ??= []).add((t['top'] as num).toDouble());
    }
    // Most recently trained first; three unless opened up.
    final progressRows = progress.entries.toList().reversed.toList();
    final shownProgress = _allProgress ? progressRows : progressRows.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        _MembershipStrip(membership: appDb.setting<Map<String, Object?>?>('membership', null), onEdit: _openMembership),
        // The figure on the left; what is picked and what is due on the right.
        AppCard(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Spacing.md,
              children: [
                BodyMap(
                  side: _side,
                  selected: _muscle,
                  stale: stale,
                  height: 252,
                  onSelect: (m) {
                    tick();
                    widget.onMuscle(m);
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Spacing.sm,
                    children: [
                      Segmented<String>(
                        value: _side,
                        onChanged: (v) => setState(() => _side = v),
                        options: const {'front': 'Front', 'back': 'Back'},
                      ),
                      const SizedBox(height: 2),
                      T(_muscle, variant: TextVariant.title, maxLines: 1, style: const TextStyle(fontSize: 22)),
                      T(
                        _restLabel(selectedDays),
                        variant: TextVariant.small,
                        color: stale.contains(_muscle) ? c.warn : c.textDim,
                      ),
                      const SizedBox(height: 2),
                      T(
                        upNext.isEmpty ? 'ALL RESTED UP' : 'DUE NEXT',
                        variant: TextVariant.small,
                        dim: true,
                        style: const TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w600),
                      ),
                      if (upNext.isEmpty)
                        const T('Everything was trained in the last two days.', variant: TextVariant.small, dim: true)
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in upNext)
                              AppChip(r.muscle, selected: r.muscle == _muscle, onPressed: () => _pick(r.muscle)),
                          ],
                        ),
                      T(
                        stale.isEmpty ? 'Tap a muscle on the figure.' : 'Tap a muscle. Amber ones have rested 5+ days.',
                        variant: TextVariant.small,
                        dim: true,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Section(
          title: '$_muscle exercises',
          children: [
            AppCard(
              spacing: 0,
              padding: listCardPadding,
              children: [
                for (final (i, ex) in exercises[_muscle]!.indexed)
                  ListRow(
                    divider: i > 0,
                    // The form tip stays tucked away until the row is tapped.
                    onTap: () => setState(() => _tipFor = _tipFor == ex.name ? null : ex.name),
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            T(ex.name, variant: TextVariant.label, style: const TextStyle(fontSize: 15)),
                            T(ex.dose, variant: TextVariant.small, color: c.accent),
                            if (_tipFor == ex.name) T(ex.tip, variant: TextVariant.small, dim: true),
                          ],
                        ),
                      ),
                      AppButton('Log', kind: ButtonKind.soft, small: true, onPressed: () => _openSetForm(ex.name)),
                    ],
                  ),
              ],
            ),
          ],
        ),
        if (_todaySets.isNotEmpty)
          Section(
            title: "Today's workout",
            right: T(
              '${_todaySets.length} ${_todaySets.length == 1 ? 'set' : 'sets'}',
              variant: TextVariant.small,
              dim: true,
            ),
            children: [
              AppCard(
                spacing: 0,
                padding: listCardPadding,
                children: [
                  for (final (i, group) in todayByExercise.entries.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      decoration: BoxDecoration(
                        border: i > 0 ? Border(top: BorderSide(color: c.border, width: 0.5)) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Spacing.sm,
                        children: [
                          Row(
                            spacing: Spacing.sm,
                            children: [
                              Expanded(
                                child: T(
                                  '${group.key} · ${group.value.first['muscle']}',
                                  variant: TextVariant.label,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              AppButton(
                                'Set',
                                icon: Icons.add,
                                kind: ButtonKind.soft,
                                small: true,
                                onPressed: () =>
                                    openSetSheet(context, group.value.first['muscle'] as String, group.key),
                              ),
                            ],
                          ),
                          // One chip per set; tap to remove it (with Undo).
                          Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: [
                              for (final s in group.value)
                                AppChip(
                                  '${plainNumber(s['weight'] as num)} $unit × ${s['reps']}',
                                  icon: Icons.close,
                                  onPressed: () => deleteWithUndo('workout_sets', s, 'Removed a set of ${group.key}'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        if (progressRows.isNotEmpty)
          Section(
            title: 'Progress · top weight',
            right: progressRows.length <= 3
                ? null
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _allProgress = !_allProgress),
                    child: T(
                      _allProgress ? 'Show fewer' : 'Show all ${progressRows.length}',
                      variant: TextVariant.label,
                      color: c.accent,
                    ),
                  ),
            children: [
              AppCard(
                children: [for (final p in shownProgress) _ProgressRow(exercise: p.key, values: p.value, unit: unit)],
              ),
            ],
          ),
      ],
    );
  }
}

/// One slim line for the gym membership: how long is left, or an invitation to add it.
class _MembershipStrip extends StatelessWidget {
  const _MembershipStrip({required this.membership, required this.onEdit});

  final Map<String, Object?>? membership;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = membership;
    final String title;
    final String detail;
    var color = c.textDim;
    if (m == null) {
      title = 'Gym membership';
      detail = 'Add it to track when it runs out';
    } else {
      final gym = m['gym'] as String? ?? '';
      final end = m['end'] as String;
      final price = m['price'] as String? ?? '';
      final left = daysBetween(todayKey(), end);
      color = left < 0
          ? c.danger
          : left <= 7
          ? c.warn
          : c.success;
      title = left < 0
          ? 'Membership expired'
          : left == 0
          ? 'Membership ends today'
          : '$left ${left == 1 ? 'day' : 'days'} left';
      detail = [
        if (gym.isNotEmpty) gym,
        '${left < 0 ? 'ended' : 'renews'} ${formatDay(end)}',
        if (price.isNotEmpty) price,
      ].join(' · ');
    }
    return AppCard(
      onTap: onEdit,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      children: [
        Row(
          spacing: Spacing.md,
          children: [
            Icon(Icons.card_membership, size: 22, color: color),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(title, variant: TextVariant.label, color: m == null ? c.text : color, maxLines: 1),
                  T(detail, variant: TextVariant.small, dim: true, maxLines: 1),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textDim),
          ],
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.exercise, required this.values, required this.unit});

  final String exercise;
  final List<double> values;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recent = values.length > 10 ? values.sublist(values.length - 10) : values;
    final max = recent.fold(1.0, math.max);
    final change = values.last - values.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        spacing: Spacing.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(exercise, maxLines: 1),
                T(
                  values.length == 1
                      ? '${plainNumber(values.first)} $unit — first session'
                      : '${plainNumber(values.first)} → ${plainNumber(values.last)} $unit '
                            '(${change >= 0 ? '+' : ''}${plainNumber(change)})',
                  variant: TextVariant.small,
                  color: change > 0 ? c.success : c.textDim,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 3,
              children: [
                for (final v in recent)
                  Container(
                    width: 6,
                    height: 4 + v / max * 24,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(3)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stays open after each save so several sets can be logged in a row.
class _SetForm extends StatefulWidget {
  const _SetForm({required this.initialMuscle, required this.initialExercise});

  final String initialMuscle;
  final String initialExercise;

  @override
  State<_SetForm> createState() => _SetFormState();
}

class _SetFormState extends State<_SetForm> with Live {
  late String _muscle = widget.initialMuscle;
  late final _exercise = TextEditingController(text: widget.initialExercise);
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  String _message = '';
  bool _ok = false;
  List<String> _known = [];

  /// The most recent set of the exercise named in the form, if there is one.
  Rec? _last;

  @override
  Future<void> load() async {
    final rows = await appDb.query(
      'SELECT exercise FROM workout_sets WHERE muscle = ? GROUP BY exercise ORDER BY MAX(id) DESC LIMIT 6',
      [_muscle],
    );
    final exercise = _exercise.text.trim();
    final last = exercise.isEmpty
        ? const <Rec>[]
        : await appDb.query(
            'SELECT weight, reps, date FROM workout_sets WHERE exercise = ? COLLATE NOCASE ORDER BY id DESC LIMIT 1',
            [exercise],
          );
    _known = [for (final r in rows) r['exercise'] as String];
    _last = last.firstOrNull;
    // Start from what was lifted last time, so repeating a set is one tap.
    if (_last != null && _weight.text.isEmpty && _reps.text.isEmpty) {
      _weight.text = plainNumber(_last!['weight'] as num);
      _reps.text = '${_last!['reps']}';
    }
  }

  @override
  void dispose() {
    _exercise.dispose();
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _fail(String text) => setState(() {
    _message = text;
    _ok = false;
  });

  Future<void> _save() async {
    final exercise = _exercise.text.trim();
    final w = _weight.text.trim().isEmpty ? 0.0 : double.tryParse(_weight.text.trim().replaceFirst(',', '.'));
    final r = int.tryParse(_reps.text.trim());
    if (exercise.isEmpty) return _fail('Name the exercise.');
    if (w == null || !w.isFinite || w < 0 || r == null || r <= 0) {
      return _fail('Enter the weight as a number and a whole number of reps.');
    }
    await appDb.insert('INSERT INTO workout_sets (date, muscle, exercise, weight, reps) VALUES (?, ?, ?, ?, ?)', [
      todayKey(),
      _muscle,
      exercise,
      w,
      r,
    ]);
    if (!mounted) return;
    final unit = appDb.setting('weight_unit', 'kg');
    setState(() {
      _message = 'Logged $exercise — ${plainNumber(w)} $unit × $r. Add the next set.';
      _ok = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = appDb.setting('weight_unit', 'kg');
    return FormColumn(
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final m in muscles)
              AppChip(
                m,
                selected: m == _muscle,
                onPressed: () {
                  setState(() => _muscle = m);
                  reload();
                },
              ),
          ],
        ),
        Field(label: 'Exercise', controller: _exercise, hint: 'Bench press', onChanged: (_) => reload()),
        if (_known.isNotEmpty)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final k in _known)
                AppChip(
                  k,
                  selected: k == _exercise.text,
                  onPressed: () {
                    _exercise.text = k;
                    _weight.clear();
                    _reps.clear();
                    reload();
                  },
                ),
            ],
          ),
        if (_last != null)
          T(
            'Last time (${relativeDay(_last!['date'] as String).toLowerCase()}): '
            '${plainNumber(_last!['weight'] as num)} $unit × ${_last!['reps']}',
            variant: TextVariant.small,
            dim: true,
          ),
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: Field(
                label: 'Weight ($unit)',
                controller: _weight,
                hint: '0',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            Expanded(
              child: Field(label: 'Reps', controller: _reps, hint: '10', keyboardType: TextInputType.number),
            ),
          ],
        ),
        if (_message.isNotEmpty) T(_message, color: _ok ? c.success : c.danger),
        AppButton('Log set', onPressed: _save),
      ],
    );
  }
}

class _MembershipForm extends StatefulWidget {
  const _MembershipForm({required this.membership, required this.onSave});

  final Map<String, Object?>? membership;
  final ValueChanged<Map<String, Object?>?> onSave;

  @override
  State<_MembershipForm> createState() => _MembershipFormState();
}

class _MembershipFormState extends State<_MembershipForm> {
  late final _gym = TextEditingController(text: widget.membership?['gym'] as String? ?? '');
  late final _price = TextEditingController(text: widget.membership?['price'] as String? ?? '');
  late String _start = widget.membership?['start'] as String? ?? todayKey();
  late String _end = widget.membership?['end'] as String? ?? '';
  String _error = '';

  @override
  void dispose() {
    _gym.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    if (_end.isEmpty) return setState(() => _error = 'Pick the date it ends.');
    if (_end.compareTo(_start) <= 0) {
      return setState(() => _error = 'The end date has to be after the start date.');
    }
    widget.onSave({'gym': _gym.text.trim(), 'start': _start, 'end': _end, 'price': _price.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        Field(label: 'Gym', controller: _gym, hint: 'Gym name'),
        DateField(label: 'Started', value: _start, onChanged: (d) => setState(() => _start = d)),
        DateField(label: 'Ends', value: _end, onChanged: (d) => setState(() => _end = d)),
        Field(label: 'Price (optional)', controller: _price, hint: 'e.g. 40 / month'),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Save', onPressed: _save),
        if (widget.membership != null)
          AppButton('Remove membership', kind: ButtonKind.danger, onPressed: () => widget.onSave(null)),
      ],
    );
  }
}
