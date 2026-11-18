import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../jar.dart';
import '../pickers.dart';
import '../receipt.dart';
import '../theme.dart';
import '../ui.dart';

const _kindLabel = {'expense': 'Spent', 'income': 'Income', 'saving': 'Saved'};

const _sums = '''
  SUM(CASE WHEN kind = 'income' THEN amount END) AS income,
  SUM(CASE WHEN kind = 'expense' THEN amount END) AS expense,
  SUM(CASE WHEN kind = 'saving' THEN amount END) AS saving''';

double? parseAmount(String text) {
  final n = double.tryParse(text.replaceFirst(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
  return n != null && n.isFinite && n > 0 ? n : null;
}

/// e.g. 1234.5 → "1,234.5"; at most two decimals, no trailing zeros.
String formatNumber(double n) {
  final fixed = n.abs().toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  return '${n < 0 ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String formatMoney(double n, String currency) {
  final s = formatNumber(n);
  return currency.length <= 1 ? '$currency$s' : '$s $currency';
}

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with Live {
  Rec _week = {};
  Rec _all = {};
  Map<String, double> _spentByDay = {};
  List<Rec> _recent = [];

  /// How full the jar was at the last load, to cheer when a quarter mark is passed; null before the first load.
  double? _lastFill;

  /// The budget week runs Monday to Sunday.
  String get _weekFrom => weekStart(todayKey());

  @override
  Future<void> load() async {
    final from = _weekFrom, to = addDays(from, 6);
    final week = await appDb.query('SELECT $_sums FROM transactions WHERE date BETWEEN ? AND ?', [from, to]);
    final all = await appDb.query('SELECT $_sums FROM transactions');
    final byDay = await appDb.query(
      "SELECT date, SUM(amount) AS total FROM transactions WHERE kind = 'expense' AND date BETWEEN ? AND ? "
      'GROUP BY date',
      [from, to],
    );
    final recent = await appDb.query('SELECT * FROM transactions ORDER BY date DESC, id DESC LIMIT 60');
    _week = week.first;
    _all = all.first;
    _spentByDay = {for (final r in byDay) r['date'] as String: _num(r['total'])};
    _recent = recent;

    final goal = appDb.setting<Map<String, Object?>?>('goal', null);
    final fill = jarFill(_num(_all['saving']), goal == null ? null : _num(goal['target']));
    final before = _lastFill;
    _lastFill = fill;
    final milestone = before == null ? null : jarMilestone(before, fill);
    if (milestone != null) {
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(jarCheers[milestone]!),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 84),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          ),
        );
    }
  }

  String get _currency => appDb.setting('currency', r'$');
  String _money(double n) => formatMoney(n, _currency);

  Color _kindColor(String kind) {
    final c = context.colors;
    return switch (kind) {
      'income' => c.success,
      'saving' => c.accent,
      _ => c.text,
    };
  }

  void _openAdd() {
    showSheet(
      context,
      title: 'Add transaction',
      builder: (sheet) => _TxForm(
        onSave: (kind, amount, label, date) async {
          await appDb.insert('INSERT INTO transactions (date, kind, amount, label) VALUES (?, ?, ?, ?)', [
            date,
            kind,
            amount,
            label,
          ]);
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  void _openEdit(Rec t) {
    showSheet(
      context,
      title: 'Edit transaction',
      builder: (sheet) => _TxForm(
        initial: t,
        onSave: (kind, amount, label, date) async {
          await appDb.run('UPDATE transactions SET date = ?, kind = ?, amount = ?, label = ? WHERE id = ?', [
            date,
            kind,
            amount,
            label,
            t['id'],
          ]);
          if (sheet.mounted) Navigator.pop(sheet);
        },
        onDelete: () async {
          await deleteWithUndo('transactions', t, 'Deleted ${_money(_num(t['amount']))}');
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  void _openGoal() {
    showSheet(
      context,
      title: 'Savings goal',
      builder: (sheet) => _GoalForm(
        goal: appDb.setting<Map<String, Object?>?>('goal', null),
        currency: _currency,
        onSave: (goal, currency) async {
          await appDb.setSetting('goal', goal);
          await appDb.setSetting('currency', currency);
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final weekFrom = _weekFrom;
    final goal = appDb.setting<Map<String, Object?>?>('goal', null);

    final weekIncome = _num(_week['income']);
    final weekSpent = _num(_week['expense']);
    final saved = _num(_all['saving']);
    final available = _num(_all['income']) - _num(_all['expense']) - saved;
    final daysLeft = 7 - daysBetween(weekFrom, today);
    final weekLeft = weekIncome - weekSpent - _num(_week['saving']);

    // Recent transactions, grouped under their day.
    final groups = <String, List<Rec>>{};
    for (final t in _recent) {
      (groups[t['date'] as String] ??= []).add(t);
    }

    return Screen(
      title: 'Wallet',
      subtitle: 'Available: ${_money(available)}',
      fabLabel: 'Add',
      onFab: _openAdd,
      children: [
        AppCard(
          spacing: Spacing.md,
          children: [
            const T('THIS WEEK', variant: TextVariant.label, dim: true),
            Row(
              spacing: Spacing.md,
              children: [
                _Stat(label: 'Income', value: _money(weekIncome), color: c.success),
                _Stat(label: 'Spent', value: _money(weekSpent)),
                _Stat(label: 'Today', value: _money(_spentByDay[today] ?? 0)),
              ],
            ),
            _WeekBars(from: weekFrom, spent: _spentByDay, money: _money),
            if (weekIncome > 0) ...[
              ProgressBar(weekSpent / weekIncome, color: weekSpent > weekIncome ? c.danger : c.accent),
              T(
                weekLeft >= 0
                    ? '${_money(weekLeft)} left — about ${_money(weekLeft / daysLeft)} a day for $daysLeft more '
                          '${daysLeft == 1 ? 'day' : 'days'}'
                    : "${_money(-weekLeft)} over this week's income",
                variant: TextVariant.small,
                color: weekLeft >= 0 ? c.textDim : c.danger,
              ),
            ] else
              const T(
                "Add this week's income to see how much you can spend per day.",
                variant: TextVariant.small,
                dim: true,
              ),
          ],
        ),
        AppCard(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Spacing.lg,
              children: [
                SavingsJar(
                  fill: jarFill(saved, goal == null ? null : _num(goal['target'])),
                  onTap: () => openJarDrop(context, money: _money),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Spacing.xs,
                    children: [
                      T(
                        goal != null ? (goal['name'] as String).toUpperCase() : 'SAVINGS JAR',
                        variant: TextVariant.label,
                        dim: true,
                        maxLines: 1,
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: T(_money(saved), variant: TextVariant.number, maxLines: 1),
                      ),
                      T(
                        goal != null
                            ? '${(jarFill(saved, _num(goal['target'])) * 100).round()}% of ${_money(_num(goal['target']))}'
                            : 'Set a goal and watch the jar fill up.',
                        variant: TextVariant.small,
                        dim: true,
                      ),
                      if (goal != null) T(_goalHint(goal, saved), variant: TextVariant.small, dim: true),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              spacing: Spacing.sm,
              children: [
                Expanded(
                  child: AppButton(
                    'Drop in',
                    icon: Icons.savings_outlined,
                    small: true,
                    onPressed: () => openJarDrop(context, money: _money),
                  ),
                ),
                Expanded(
                  child: AppButton(
                    goal != null ? 'Edit goal' : 'Set a goal',
                    kind: ButtonKind.soft,
                    small: true,
                    onPressed: _openGoal,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (ready && _recent.isEmpty)
          const Empty(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            hint: 'Tap “Add” to log income, spending or money you put aside.',
          ),
        for (final g in groups.entries)
          Section(
            title: relativeDay(g.key),
            right: T(_dayTotal(g.value), variant: TextVariant.small, dim: true),
            children: [
              AppCard(
                spacing: 0,
                padding: listCardPadding,
                children: [for (final (i, t) in g.value.indexed) _txRow(t, divider: i > 0)],
              ),
            ],
          ),
      ],
    );
  }

  /// What the day did to the money available: income minus spending and savings.
  String _dayTotal(List<Rec> txs) {
    var net = 0.0;
    for (final t in txs) {
      net += t['kind'] == 'income' ? _num(t['amount']) : -_num(t['amount']);
    }
    return '${net >= 0 ? '+' : '−'}${_money(net.abs())}';
  }

  Widget _txRow(Rec t, {required bool divider}) {
    final c = context.colors;
    final kind = t['kind'] as String;
    final label = t['label'] as String;
    final sign = switch (kind) {
      'income' => '+',
      'expense' => '−',
      _ => '',
    };
    final (icon, tint) = switch (kind) {
      'income' => (Icons.south_west, c.success),
      'saving' => (Icons.savings_outlined, c.accent),
      _ => (Icons.north_east, c.textDim),
    };
    return ListRow(
      divider: divider,
      onTap: () => _openEdit(t),
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: tint),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              T(label.isNotEmpty ? label : _kindLabel[kind]!, maxLines: 1),
              if (label.isNotEmpty) T(_kindLabel[kind]!, variant: TextVariant.small, dim: true),
            ],
          ),
        ),
        T('$sign${_money(_num(t['amount']))}', variant: TextVariant.heading, color: _kindColor(kind)),
      ],
    );
  }

  String _goalHint(Map<String, Object?> goal, double saved) {
    final left = _num(goal['target']) - saved;
    final deadline = goal['deadline'] as String? ?? '';
    if (left <= 0) return 'Goal reached.';
    if (deadline.isEmpty) return '${_money(left)} to go.';
    final days = daysBetween(todayKey(), deadline);
    if (days <= 0) return '${_money(left)} to go — the target date has passed.';
    final weeks = math.max(1, (days / 7).ceil());
    return '${_money(left)} to go — ${_money(left / weeks)} a week for $weeks ${weeks == 1 ? 'week' : 'weeks'}.';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          T(label, variant: TextVariant.small, dim: true),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: T(value, variant: TextVariant.heading, color: color, maxLines: 1),
          ),
        ],
      ),
    );
  }
}

/// Spending for each day of the week as bars; today stands out, days ahead are faint.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.from, required this.spent, required this.money});

  final String from;
  final Map<String, double> spent;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final days = dateRange(from, addDays(from, 6));
    final top = days.fold(0.0, (m, d) => math.max(m, spent[d] ?? 0));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: Spacing.sm,
      children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              label: '${formatDay(d)}: ${money(spent[d] ?? 0)} spent',
              excludeSemantics: true,
              child: Column(
                spacing: 4,
                children: [
                  SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: top > 0 ? (spent[d] ?? 0) / top : 0),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Container(
                          height: 4 + 40 * v,
                          decoration: BoxDecoration(
                            color: d == today
                                ? c.accent
                                : d.compareTo(today) > 0
                                ? c.surfaceAlt
                                : c.textDim.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  T(
                    weekdays[weekdayOf(d)].substring(0, 1),
                    variant: TextVariant.small,
                    color: d == today ? c.accent : c.textDim,
                    style: TextStyle(fontSize: 11, fontWeight: d == today ? FontWeight.w700 : FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TxForm extends StatefulWidget {
  const _TxForm({required this.onSave, this.initial, this.onDelete});

  /// A transactions row to edit; null for a new one.
  final Rec? initial;
  final void Function(String kind, double amount, String label, String date) onSave;
  final VoidCallback? onDelete;

  @override
  State<_TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<_TxForm> {
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : plainNumber(widget.initial!['amount'] as num),
  );
  late final _label = TextEditingController(text: widget.initial?['label'] as String? ?? '');
  late String _kind = widget.initial?['kind'] as String? ?? 'expense';
  late String _date = widget.initial?['date'] as String? ?? todayKey();
  String _error = '';

  /// What the last receipt scan came to, shown under the scan buttons.
  String _scanNote = '';
  bool _scanning = false;

  /// The total and the other prices the last scan found, offered as chips so a misread total is one tap to fix.
  List<double> _found = [];

  /// An amount as it goes in the field: up to three decimals, for currencies that have them, and no trailing zeros.
  static String _amountText(double n) => n.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final n = parseAmount(_amount.text);
    if (n == null) return setState(() => _error = 'Enter an amount above zero.');
    widget.onSave(_kind, n, _label.text.trim(), _date);
  }

  /// Reads a receipt from the camera or a saved photo and fills in what it can.
  Future<void> _scan({required bool camera}) async {
    if (_scanning) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _scanning = true);
    var note = _scanNote;
    var found = _found;
    try {
      final text = await readReceiptText(camera: camera);
      if (!mounted) return;
      if (text != null) {
        final receipt = parseReceipt(text, currency: appDb.setting('currency', r'$'));
        if (receipt.amount != null) _amount.text = _amountText(receipt.amount!);
        if (receipt.label.isNotEmpty) _label.text = receipt.label;
        if (receipt.date != null) _date = receipt.date!;
        _kind = 'expense';
        found = [?receipt.amount, ...receipt.amounts];
        note = receipt.amount == null
            ? (text.trim().isEmpty
                  ? 'No writing showed up in that picture. Hold the receipt flat, fill the frame and try again.'
                  : 'No total could be read. Type the amount in.')
            : found.length > 1
            ? 'Check the total before saving. Wrong one? Tap the right amount.'
            : 'Filled in from the receipt. Check it before saving.';
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Receipt scan: $e');
      final denied = e.toString().contains('access_denied');
      note = denied
          ? 'HYETI may not use the ${camera ? 'camera' : 'photos'}. Allow it in Android settings, then try again.'
          : 'The picture could not be read ($e). Try again, or type the amount in.';
      found = [];
    }
    setState(() {
      _scanning = false;
      _scanNote = note;
      _found = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        if (widget.initial == null) ...[
          Row(
            spacing: Spacing.sm,
            children: [
              Expanded(
                child: AppButton(
                  _scanning ? 'Reading…' : 'Scan receipt',
                  kind: ButtonKind.soft,
                  icon: Icons.document_scanner_outlined,
                  onPressed: _scanning ? null : () => _scan(camera: true),
                ),
              ),
              Expanded(
                child: AppButton(
                  'From a photo',
                  kind: ButtonKind.soft,
                  icon: Icons.photo_library_outlined,
                  onPressed: _scanning ? null : () => _scan(camera: false),
                ),
              ),
            ],
          ),
          if (_scanNote.isNotEmpty) T(_scanNote, variant: TextVariant.small, dim: true),
          if (_found.length > 1)
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final n in _found)
                  AppChip(
                    _amountText(n),
                    selected: parseAmount(_amount.text) == n,
                    onPressed: () => setState(() => _amount.text = _amountText(n)),
                  ),
              ],
            ),
        ],
        Segmented<String>(value: _kind, onChanged: (v) => setState(() => _kind = v), options: _kindLabel),
        Field(
          label: 'Amount',
          controller: _amount,
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          autofocus: widget.initial == null,
        ),
        Field(
          label: 'What for (optional)',
          controller: _label,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          hint: switch (_kind) {
            'income' => 'Salary',
            'saving' => 'Put aside',
            _ => 'Groceries',
          },
        ),
        DateField(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d)),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Save', onPressed: _save),
        if (widget.onDelete != null) AppButton('Delete', kind: ButtonKind.danger, onPressed: widget.onDelete),
      ],
    );
  }
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.goal, required this.currency, required this.onSave});

  final Map<String, Object?>? goal;
  final String currency;
  final void Function(Map<String, Object?>? goal, String currency) onSave;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final _name = TextEditingController(text: widget.goal?['name'] as String? ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : plainNumber(_num(widget.goal!['target'])),
  );
  late final _symbol = TextEditingController(text: widget.currency);
  late String _deadline = widget.goal?['deadline'] as String? ?? '';
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _symbol.dispose();
    super.dispose();
  }

  String get _currency => _symbol.text.trim().isEmpty ? r'$' : _symbol.text.trim();

  void _save() {
    final n = parseAmount(_target.text);
    if (n == null) return setState(() => _error = 'Enter a target amount above zero.');
    final name = _name.text.trim();
    widget.onSave({'name': name.isEmpty ? 'Savings goal' : name, 'target': n, 'deadline': _deadline}, _currency);
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        Field(label: 'Saving for', controller: _name, hint: 'New laptop', textInputAction: TextInputAction.next),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: Field(
                label: 'Target amount',
                controller: _target,
                hint: '1000',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            Expanded(
              child: Field(
                label: 'Currency',
                controller: _symbol,
                hint: r'$',
                capitalization: TextCapitalization.characters,
              ),
            ),
          ],
        ),
        DateField(
          label: 'Target date',
          value: _deadline,
          onChanged: (d) => setState(() => _deadline = d),
          optional: true,
        ),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Save goal', onPressed: _save),
        if (widget.goal != null)
          AppButton('Remove goal', kind: ButtonKind.danger, onPressed: () => widget.onSave(null, _currency)),
      ],
    );
  }
}
