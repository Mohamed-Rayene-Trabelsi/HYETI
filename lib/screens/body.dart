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

  /// Carries on with the exercise logged last today if it belongs to the picked muscle;
  /// otherwise starts that muscle's first exercise.
  Future<void> _logSet() async {
    final last = await appDb.query(
      'SELECT exercise FROM workout_sets WHERE date = ? AND muscle = ? ORDER BY id DESC LIMIT 1',
      [todayKey(), _muscle],
    );
    if (!mounted) return;
    openSetSheet(context, _muscle, last.isEmpty ? exercises[_muscle]!.first.name : last.first['exercise'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final gym = _tab == 'gym';
    return Screen(
      title: 'Body',
      fabLabel: gym ? 'Log set' : 'Log food',
      onFab: gym ? _logSet : () => openFoodSheet(context),
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

/// Opens the set logger for one exercise. An empty [exercise] asks for a name first.
void openSetSheet(BuildContext context, String muscle, String exercise) {
  showSheet(
    context,
    title: exercise.isEmpty ? 'Another $muscle exercise' : exercise,
    builder: (_) => _SetForm(muscle: muscle, exercise: exercise),
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

  bool _allProgress = false;

  /// False until the opening muscle has been chosen from what was trained.
  bool _opened = false;

  List<Rec> _lastTrained = [];
  List<Rec> _todaySets = [];
  List<Rec> _tops = [];

  /// The most recent set of every exercise ever logged.
  List<Rec> _latest = [];

  @override
  Future<void> load() async {
    final last = await appDb.query('SELECT muscle, MAX(date) AS last FROM workout_sets GROUP BY muscle');
    final sets = await appDb.query('SELECT * FROM workout_sets WHERE date = ? ORDER BY id', [todayKey()]);
    final tops = await appDb.query(
      'SELECT exercise, date, MAX(weight) AS top FROM workout_sets GROUP BY exercise, date ORDER BY date',
    );
    final latest = await appDb.query(
      'SELECT muscle, exercise, weight, reps FROM workout_sets '
      'WHERE id IN (SELECT MAX(id) FROM workout_sets GROUP BY exercise) ORDER BY id DESC',
    );
    _lastTrained = last;
    _todaySets = sets;
    _tops = tops;
    _latest = latest;

    // Open on what is being trained today, or else on the muscle that has waited longest,
    // so the right exercises are already on screen.
    if (!_opened && mounted) {
      _opened = true;
      String? start;
      if (sets.isNotEmpty) {
        start = sets.last['muscle'] as String;
      } else if (last.isNotEmpty) {
        start =
            (last.toList()..sort((a, b) => (a['last'] as String).compareTo(b['last'] as String))).first['muscle']
                as String;
      }
      if (start != null && start != _muscle && muscles.contains(start)) _pick(start);
    }
  }

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

  /// One exercise: the whole row opens its logger.
  Widget _exerciseRow(BuildContext context, {required bool divider, required String name, String? dose}) {
    final c = context.colors;
    final unit = appDb.setting('weight_unit', 'kg');
    final key = name.toLowerCase();
    final today = _todaySets.where((s) => (s['exercise'] as String).toLowerCase() == key).length;
    final last = _latest.where((s) => (s['exercise'] as String).toLowerCase() == key).firstOrNull;
    return ListRow(
      divider: divider,
      onTap: () => openSetSheet(context, _muscle, name),
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              T(name, variant: TextVariant.label, maxLines: 1, style: const TextStyle(fontSize: 15)),
              if (dose != null) T(dose, variant: TextVariant.small, color: c.accent),
            ],
          ),
        ),
        if (today > 0)
          T('$today ${today == 1 ? 'set' : 'sets'} today', variant: TextVariant.small, color: c.success)
        else if (last != null)
          T('${plainNumber(last['weight'] as num)} $unit × ${last['reps']}', variant: TextVariant.small, dim: true),
        Icon(Icons.chevron_right, color: c.textDim),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final unit = appDb.setting('weight_unit', 'kg');
    final membership = appDb.setting<Map<String, Object?>?>('membership', null);
    // The membership only earns the top of the screen when it is about to run out.
    final membershipDue = membership != null && daysBetween(today, membership['end'] as String) <= 7;
    final membershipStrip = _MembershipStrip(membership: membership, onEdit: _openMembership);

    // Longest-rested muscles first; never-trained ones lead.
    final lastByMuscle = {for (final r in _lastTrained) r['muscle'] as String: r['last'] as String};
    final rest = [
      for (final m in muscles) (muscle: m, days: lastByMuscle[m] == null ? null : daysBetween(lastByMuscle[m]!, today)),
    ]..sort((a, b) => (b.days ?? 9999) - (a.days ?? 9999));
    // Amber marks muscles that have been trained before and then left for five days or more.
    final stale = _lastTrained.isEmpty
        ? <String>[]
        : [
            for (final r in rest)
              if (r.days != null && r.days! >= 5) r.muscle,
          ];
    final selectedDays = rest.firstWhere((r) => r.muscle == _muscle).days;

    final builtIn = exercises[_muscle]!;
    final builtInNames = {for (final ex in builtIn) ex.name.toLowerCase()};
    // Exercises the user named themselves for this muscle, most recent first.
    final own = [
      for (final s in _latest)
        if (s['muscle'] == _muscle && !builtInNames.contains((s['exercise'] as String).toLowerCase()))
          s['exercise'] as String,
    ];

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
        if (membershipDue) membershipStrip,
        // The figure on the left; what is picked on the right.
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
                  height: 220,
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
                        stale.isEmpty
                            ? 'Tap a muscle, then an exercise below.'
                            : 'Tap a muscle, then an exercise below. Amber has rested 5+ days.',
                        variant: TextVariant.small,
                        dim: true,
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
                for (final (i, ex) in builtIn.indexed)
                  _exerciseRow(context, divider: i > 0, name: ex.name, dose: ex.dose),
                for (final name in own) _exerciseRow(context, divider: true, name: name),
                ListRow(
                  divider: true,
                  onTap: () => openSetSheet(context, _muscle, ''),
                  children: [
                    Expanded(child: T('Something else', variant: TextVariant.label, dim: true)),
                    Icon(Icons.add, color: c.textDim),
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
                          T(
                            '${group.key} · ${group.value.first['muscle']}',
                            variant: TextVariant.label,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 15),
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
        if (!membershipDue) membershipStrip,
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

/// Logs sets of one exercise. Weight and reps start from the last set, so repeating it is one tap,
/// and the sheet stays open for the next set.
class _SetForm extends StatefulWidget {
  const _SetForm({required this.muscle, required this.exercise});

  final String muscle;

  /// Empty when the user is about to name an exercise of their own.
  final String exercise;

  @override
  State<_SetForm> createState() => _SetFormState();
}

class _SetFormState extends State<_SetForm> with Live {
  late final _name = TextEditingController(text: widget.exercise);
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  String _message = '';
  bool _ok = false;

  /// The most recent set of this exercise, if there is one.
  Rec? _last;
  List<Rec> _today = [];

  Exercise? get _preset =>
      exercises[widget.muscle]!.where((e) => e.name.toLowerCase() == _name.text.trim().toLowerCase()).firstOrNull;

  @override
  Future<void> load() async {
    final exercise = _name.text.trim();
    if (exercise.isEmpty) {
      _last = null;
      _today = [];
      return;
    }
    final last = await appDb.query(
      'SELECT weight, reps, date FROM workout_sets WHERE exercise = ? COLLATE NOCASE ORDER BY id DESC LIMIT 1',
      [exercise],
    );
    final today = await appDb.query(
      'SELECT weight, reps FROM workout_sets WHERE date = ? AND exercise = ? COLLATE NOCASE ORDER BY id',
      [todayKey(), exercise],
    );
    _last = last.firstOrNull;
    _today = today;
    // Start from what was lifted last time, or from the low end of the suggested reps.
    if (_weight.text.isEmpty && _reps.text.isEmpty) {
      if (_last != null) {
        _weight.text = plainNumber(_last!['weight'] as num);
        _reps.text = '${_last!['reps']}';
      } else {
        _reps.text = RegExp(r'×\s*(\d+)').firstMatch(_preset?.dose ?? '')?.group(1) ?? '10';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  double? get _weightValue =>
      _weight.text.trim().isEmpty ? 0.0 : double.tryParse(_weight.text.trim().replaceFirst(',', '.'));

  void _nudgeWeight(double by) {
    tick();
    final next = math.max(0.0, (_weightValue ?? 0) + by);
    setState(() => _weight.text = plainNumber(next));
  }

  void _nudgeReps(int by) {
    tick();
    final next = math.max(1, (int.tryParse(_reps.text.trim()) ?? 0) + by);
    setState(() => _reps.text = '$next');
  }

  void _fail(String text) => setState(() {
    _message = text;
    _ok = false;
  });

  Future<void> _save() async {
    final exercise = _name.text.trim();
    final w = _weightValue;
    final r = int.tryParse(_reps.text.trim());
    if (exercise.isEmpty) return _fail('Name the exercise.');
    if (w == null || !w.isFinite || w < 0 || r == null || r <= 0) {
      return _fail('Enter the weight as a number and a whole number of reps.');
    }
    final number = _today.length + 1;
    await appDb.insert('INSERT INTO workout_sets (date, muscle, exercise, weight, reps) VALUES (?, ?, ?, ?, ?)', [
      todayKey(),
      widget.muscle,
      exercise,
      w,
      r,
    ]);
    if (!mounted) return;
    setState(() {
      _message = 'Set $number logged. Change the numbers or tap again for the next one.';
      _ok = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = appDb.setting('weight_unit', 'kg');
    final preset = _preset;
    return FormColumn(
      children: [
        if (widget.exercise.isEmpty)
          Field(label: 'Exercise', controller: _name, hint: 'Name it', autofocus: true, onChanged: (_) => reload()),
        if (preset != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              T('${widget.muscle} · ${preset.dose}', variant: TextVariant.label, color: c.accent),
              T(preset.tip, variant: TextVariant.small, dim: true),
            ],
          ),
        // A set from today is already listed under "Today" below.
        if (_last != null && _last!['date'] != todayKey())
          T(
            'Last time (${relativeDay(_last!['date'] as String).toLowerCase()}): '
            '${plainNumber(_last!['weight'] as num)} $unit × ${_last!['reps']}',
            variant: TextVariant.small,
            dim: true,
          ),
        _Stepper(
          label: 'Weight ($unit)',
          controller: _weight,
          hint: '0',
          decimal: true,
          onLess: () => _nudgeWeight(unit == 'lb' ? -5 : -2.5),
          onMore: () => _nudgeWeight(unit == 'lb' ? 5 : 2.5),
        ),
        _Stepper(
          label: 'Reps',
          controller: _reps,
          hint: '10',
          onLess: () => _nudgeReps(-1),
          onMore: () => _nudgeReps(1),
        ),
        if (_today.isNotEmpty)
          T(
            'Today: ${[for (final s in _today) '${plainNumber(s['weight'] as num)} × ${s['reps']}'].join('  ·  ')}',
            variant: TextVariant.small,
            dim: true,
          ),
        if (_message.isNotEmpty) T(_message, variant: TextVariant.small, color: _ok ? c.success : c.danger),
        AppButton('Log set', onPressed: _save),
      ],
    );
  }
}

/// A number with a big minus and plus either side, for one-handed use between sets.
/// The number itself can still be typed.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onLess,
    required this.onMore,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final bool decimal;

  Widget _button(BuildContext context, IconData icon, String name, VoidCallback onTap) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$name $label',
      excludeSemantics: true,
      child: Material(
        color: c.surfaceAlt,
        shape: buttonShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 64, height: 52, child: Icon(icon, color: c.text, size: 24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.xs,
      children: [
        T(label, variant: TextVariant.label, dim: true, maxLines: 1),
        Row(
          spacing: Spacing.sm,
          children: [
            _button(context, Icons.remove, 'Less', onLess),
            Expanded(
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(decimal: decimal),
                style: textStyle(context, TextVariant.number).copyWith(fontSize: 22),
                decoration: fieldDecoration(context, hint: hint),
              ),
            ),
            _button(context, Icons.add, 'More', onMore),
          ],
        ),
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
