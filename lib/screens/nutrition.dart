import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../theme.dart';
import '../ui.dart';

typedef Plan = ({int kcal, int protein, int carbs, int fat});

final _activity = <num, String>{1.2: 'Mostly sitting', 1.375: 'Light', 1.55: 'Gym 3–5×/week', 1.725: 'Very active'};
const _goals = {-400: 'Lose fat', 0: 'Maintain', 300: 'Build muscle'};

const _decimal = TextInputType.numberWithOptions(decimal: true);

/// Calorie and macro targets from body stats: Mifflin-St Jeor resting energy × activity,
/// adjusted for the goal; protein 1.8 g/kg, fat 25% of calories, the rest carbs.
Plan? suggestPlan({
  required String sex,
  required String age,
  required String height,
  required String weight,
  required num activity,
  required num goal,
}) {
  final a = double.tryParse(age.trim());
  final h = double.tryParse(height.trim());
  final w = double.tryParse(weight.trim().replaceFirst(',', '.'));
  if (a == null || h == null || w == null) return null;
  if (a < 14 || a > 100 || h < 120 || h > 230 || w < 35 || w > 250) return null;
  final resting = 10 * w + 6.25 * h - 5 * a + (sex == 'male' ? 5 : -161);
  final kcal = ((resting * activity + goal) / 10).round() * 10;
  final protein = (w * 1.8).round();
  final fat = (kcal * 0.25 / 9).round();
  final carbs = math.max(0, ((kcal - protein * 4 - fat * 9) / 4).round());
  return (kcal: kcal, protein: protein, carbs: carbs, fat: fat);
}

double? _parse(String text) {
  final n = double.tryParse(text.trim().replaceFirst(',', '.'));
  return n != null && n.isFinite && n >= 0 ? n : null;
}

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

Plan? _planFrom(Map<String, Object?>? m) {
  if (m == null) return null;
  return (
    kcal: _num(m['kcal']).round(),
    protein: _num(m['protein']).round(),
    carbs: _num(m['carbs']).round(),
    fat: _num(m['fat']).round(),
  );
}

Map<String, Object?> _planJson(Plan p) => {'kcal': p.kcal, 'protein': p.protein, 'carbs': p.carbs, 'fat': p.fat};

void openFoodSheet(BuildContext context) {
  showSheet(
    context,
    title: 'Log food',
    builder: (sheet) => _FoodForm(
      onSave: (name, kcal, protein, carbs, fat) async {
        await appDb.insert('INSERT INTO food_logs (date, name, kcal, protein, carbs, fat) VALUES (?, ?, ?, ?, ?, ?)', [
          todayKey(),
          name,
          kcal,
          protein,
          carbs,
          fat,
        ]);
        if (sheet.mounted) Navigator.pop(sheet);
      },
    ),
  );
}

class Nutrition extends StatefulWidget {
  const Nutrition({super.key});

  @override
  State<Nutrition> createState() => _NutritionState();
}

class _NutritionState extends State<Nutrition> with Live {
  List<Rec> _foods = [];
  double? _weekAvg;

  @override
  Future<void> load() async {
    final today = todayKey();
    final foods = await appDb.query('SELECT * FROM food_logs WHERE date = ? ORDER BY id', [today]);
    final avg = await appDb.query(
      'SELECT AVG(total) AS avg FROM (SELECT SUM(kcal) AS total FROM food_logs WHERE date BETWEEN ? AND ? GROUP BY date)',
      [addDays(today, -7), addDays(today, -1)],
    );
    _foods = foods;
    _weekAvg = (avg.first['avg'] as num?)?.toDouble();
  }

  void _openPlan() {
    showSheet(
      context,
      title: 'Nutrition plan',
      builder: (sheet) => _PlanForm(
        plan: _planFrom(appDb.setting<Map<String, Object?>?>('nutrition_plan', null)),
        onSave: (p) async {
          await appDb.setSetting('nutrition_plan', p == null ? null : _planJson(p));
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plan = _planFrom(appDb.setting<Map<String, Object?>?>('nutrition_plan', null));
    double sum(String key) => _foods.fold(0.0, (a, f) => a + _num(f[key]));
    final kcal = sum('kcal');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        AppCard(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const T('TODAY', variant: TextVariant.label, dim: true),
                AppButton(
                  plan != null ? 'Edit plan' : 'Set a plan',
                  kind: ButtonKind.plain,
                  small: true,
                  onPressed: _openPlan,
                ),
              ],
            ),
            Text.rich(
              TextSpan(
                text: '${kcal.round()}',
                children: [
                  TextSpan(
                    text: plan != null ? ' of ${plan.kcal} kcal' : ' kcal',
                    style: textStyle(context, TextVariant.body, dim: true),
                  ),
                ],
              ),
              style: textStyle(context, TextVariant.number),
            ),
            if (plan != null) ...[
              ProgressBar(kcal / plan.kcal, color: kcal > plan.kcal ? c.warn : c.accent),
              T(
                kcal <= plan.kcal
                    ? '${(plan.kcal - kcal).round()} kcal left today'
                    : '${(kcal - plan.kcal).round()} kcal over your target',
                variant: TextVariant.small,
                dim: true,
              ),
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Row(
                  spacing: Spacing.md,
                  children: [
                    _Macro('Protein', sum('protein'), plan.protein, const Color(0xFFFF7A59)),
                    _Macro('Carbs', sum('carbs'), plan.carbs, const Color(0xFF3DBE7F)),
                    _Macro('Fat', sum('fat'), plan.fat, const Color(0xFFF5B94A)),
                  ],
                ),
              ),
            ] else
              const T(
                'Set a plan to get daily calorie and macro targets — suggested from your body stats, '
                'or typed in yourself.',
                variant: TextVariant.small,
                dim: true,
              ),
            if (_weekAvg != null && _weekAvg! > 0)
              T('Average over the last 7 days: ${_weekAvg!.round()} kcal', variant: TextVariant.small, dim: true),
          ],
        ),
        Section(
          title: 'Eaten today',
          children: [
            if (ready && _foods.isEmpty)
              const Empty(
                icon: Icons.restaurant_outlined,
                title: 'Nothing logged today',
                hint: 'Tap “Log food” to add meals and snacks and see how the day adds up.',
              )
            else if (_foods.isNotEmpty)
              AppCard(
                spacing: 0,
                padding: listCardPadding,
                children: [
                  for (final (i, f) in _foods.indexed)
                    ListRow(
                      divider: i > 0,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              T(f['name'] as String, maxLines: 1),
                              T(
                                'P ${_num(f['protein']).round()} · C ${_num(f['carbs']).round()} · '
                                'F ${_num(f['fat']).round()} g',
                                variant: TextVariant.small,
                                dim: true,
                              ),
                            ],
                          ),
                        ),
                        T('${_num(f['kcal']).round()} kcal', variant: TextVariant.heading),
                        AppButton(
                          'Remove',
                          kind: ButtonKind.plain,
                          small: true,
                          onPressed: () => deleteWithUndo('food_logs', f, 'Removed ${f['name']}'),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.value, this.target, this.color);

  final String label;
  final double value;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          T(label, variant: TextVariant.small, dim: true),
          T('${value.round()} / $target g', variant: TextVariant.label, maxLines: 1),
          ProgressBar(target > 0 ? value / target : 0, color: color),
        ],
      ),
    );
  }
}

class _FoodForm extends StatefulWidget {
  const _FoodForm({required this.onSave});

  final void Function(String name, double kcal, double protein, double carbs, double fat) onSave;

  @override
  State<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends State<_FoodForm> with Live {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  String _error = '';
  List<Rec> _recent = [];

  /// Foods logged before, most recent first, for one-tap refill.
  @override
  Future<void> load() async {
    _recent = await appDb.query(
      'SELECT * FROM food_logs WHERE id IN (SELECT MAX(id) FROM food_logs GROUP BY name) ORDER BY id DESC LIMIT 8',
    );
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Rec f) => setState(() {
    _name.text = f['name'] as String;
    _kcal.text = plainNumber(f['kcal'] as num);
    _protein.text = plainNumber(f['protein'] as num);
    _carbs.text = plainNumber(f['carbs'] as num);
    _fat.text = plainNumber(f['fat'] as num);
  });

  void _save() {
    final name = _name.text.trim();
    String orZero(TextEditingController c) => c.text.trim().isEmpty ? '0' : c.text;
    final k = _parse(_kcal.text), p = _parse(orZero(_protein)), c = _parse(orZero(_carbs)), f = _parse(orZero(_fat));
    if (name.isEmpty) return setState(() => _error = 'Name the food.');
    if (k == null || p == null || c == null || f == null) {
      return setState(() => _error = 'Enter calories, and numbers only for the macros.');
    }
    widget.onSave(name, k, p, c, f);
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        if (_recent.isNotEmpty)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final f in _recent)
                AppChip(f['name'] as String, selected: f['name'] == _name.text, onPressed: () => _fill(f)),
            ],
          ),
        Field(label: 'Food', controller: _name, hint: 'Chicken and rice', onChanged: (_) => setState(() {})),
        Field(label: 'Calories (kcal)', controller: _kcal, hint: '0', keyboardType: _decimal),
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: Field(label: 'Protein (g)', controller: _protein, hint: '0', keyboardType: _decimal),
            ),
            Expanded(
              child: Field(label: 'Carbs (g)', controller: _carbs, hint: '0', keyboardType: _decimal),
            ),
            Expanded(
              child: Field(label: 'Fat (g)', controller: _fat, hint: '0', keyboardType: _decimal),
            ),
          ],
        ),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Log food', onPressed: _save),
      ],
    );
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm({required this.plan, required this.onSave});

  final Plan? plan;
  final ValueChanged<Plan?> onSave;

  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  late bool _suggest = widget.plan == null;

  // Body stats, remembered between visits.
  final Map<String, Object?> _profile = appDb.setting<Map<String, Object?>>('nutrition_profile', const {});
  late String _sex = _profile['sex'] as String? ?? 'male';
  late num _activityLevel = _profile['activity'] as num? ?? 1.55;
  late num _goal = _profile['goal'] as num? ?? 0;
  late final _age = TextEditingController(text: _profile['age'] as String? ?? '');
  late final _height = TextEditingController(text: _profile['height'] as String? ?? '');
  late final _weight = TextEditingController(text: _profile['weight'] as String? ?? '');

  late final _kcal = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.kcal}');
  late final _protein = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.protein}');
  late final _carbs = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.carbs}');
  late final _fat = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.fat}');
  String _error = '';

  @override
  void dispose() {
    for (final c in [_age, _height, _weight, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveManual() {
    final k = _parse(_kcal.text), p = _parse(_protein.text), c = _parse(_carbs.text), f = _parse(_fat.text);
    if (k == null || p == null || c == null || f == null || k == 0) {
      return setState(() => _error = 'Fill in all four targets with numbers.');
    }
    widget.onSave((kcal: k.round(), protein: p.round(), carbs: c.round(), fat: f.round()));
  }

  Future<void> _useSuggestion(Plan suggestion) async {
    await appDb.setSetting('nutrition_profile', {
      'sex': _sex,
      'age': _age.text,
      'height': _height.text,
      'weight': _weight.text,
      'activity': _activityLevel,
      'goal': _goal,
    });
    widget.onSave(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final suggestion = suggestPlan(
      sex: _sex,
      age: _age.text,
      height: _height.text,
      weight: _weight.text,
      activity: _activityLevel,
      goal: _goal,
    );
    void refresh(String _) => setState(() {});

    return FormColumn(
      children: [
        Segmented<bool>(
          value: _suggest,
          onChanged: (v) => setState(() => _suggest = v),
          options: const {true: 'Suggest for me', false: 'Set manually'},
        ),
        if (_suggest) ...[
          Segmented<String>(
            value: _sex,
            onChanged: (v) => setState(() => _sex = v),
            options: const {'male': 'Male', 'female': 'Female'},
          ),
          Row(
            spacing: Spacing.sm,
            children: [
              Expanded(
                child: Field(
                  label: 'Age',
                  controller: _age,
                  hint: '25',
                  keyboardType: TextInputType.number,
                  onChanged: refresh,
                ),
              ),
              Expanded(
                child: Field(
                  label: 'Height (cm)',
                  controller: _height,
                  hint: '178',
                  keyboardType: TextInputType.number,
                  onChanged: refresh,
                ),
              ),
              Expanded(
                child: Field(
                  label: 'Weight (kg)',
                  controller: _weight,
                  hint: '75',
                  keyboardType: _decimal,
                  onChanged: refresh,
                ),
              ),
            ],
          ),
          const T('Activity', variant: TextVariant.label, dim: true),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final a in _activity.entries)
                AppChip(
                  a.value,
                  selected: a.key == _activityLevel,
                  onPressed: () => setState(() => _activityLevel = a.key),
                ),
            ],
          ),
          const T('Goal', variant: TextVariant.label, dim: true),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final g in _goals.entries)
                AppChip(g.value, selected: g.key == _goal, onPressed: () => setState(() => _goal = g.key)),
            ],
          ),
          if (suggestion != null)
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Spacing.sm,
                children: [
                  T('${suggestion.kcal} kcal / day', variant: TextVariant.number),
                  T(
                    'Protein ${suggestion.protein} g · Carbs ${suggestion.carbs} g · Fat ${suggestion.fat} g',
                    dim: true,
                  ),
                  const T(
                    'An estimate from standard formulas, not medical advice. Adjust after a couple of weeks '
                    'if your weight is not moving the way you want.',
                    variant: TextVariant.small,
                    dim: true,
                  ),
                ],
              ),
            )
          else
            const T('Fill in age, height and weight to see a suggested plan.', dim: true),
          AppButton('Use this plan', onPressed: suggestion == null ? null : () => _useSuggestion(suggestion)),
        ] else ...[
          Field(label: 'Calories (kcal / day)', controller: _kcal, hint: '2400', keyboardType: TextInputType.number),
          Row(
            spacing: Spacing.sm,
            children: [
              Expanded(
                child: Field(
                  label: 'Protein (g)',
                  controller: _protein,
                  hint: '140',
                  keyboardType: TextInputType.number,
                ),
              ),
              Expanded(
                child: Field(label: 'Carbs (g)', controller: _carbs, hint: '280', keyboardType: TextInputType.number),
              ),
              Expanded(
                child: Field(label: 'Fat (g)', controller: _fat, hint: '70', keyboardType: TextInputType.number),
              ),
            ],
          ),
          if (_error.isNotEmpty) T(_error, color: c.danger),
          AppButton('Save plan', onPressed: _saveManual),
        ],
        if (widget.plan != null)
          AppButton('Remove plan', kind: ButtonKind.danger, onPressed: () => widget.onSave(null)),
      ],
    );
  }
}
