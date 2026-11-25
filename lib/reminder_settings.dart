import 'package:material_ui/material_ui.dart';

import 'db.dart';
import 'reminders.dart';
import 'theme.dart';
import 'ui.dart';
import 'update.dart' show onIOS;

const _denied = 'HYETI may not show notifications. Allow them for HYETI in the phone\'s settings, then try again.';

/// Settings → Reminders: off, or how long before each block.
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  bool _busy = false;
  String _note = '';

  Future<void> _choose(int? lead) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = '';
    });
    var note = '';
    if (lead == null) {
      await turnOffReminders();
    } else if (!await turnOnReminders(lead)) {
      note = _denied;
    }
    await appDb.setSetting('reminder_asked', true);
    if (mounted) {
      setState(() {
        _busy = false;
        _note = note;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lead = reminderLead();
    return FormColumn(
      children: [
        const T(
          'A notification before each calendar block, and one three days before the gym membership ends. Ticked-off '
          'blocks stay quiet, and so do work blocks on days off.',
          dim: true,
        ),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            AppChip('Off', selected: lead == null, onPressed: _busy ? null : () => _choose(null)),
            for (final MapEntry(key: minutes, value: label) in reminderLeads.entries)
              AppChip(label, selected: lead == minutes, onPressed: _busy ? null : () => _choose(minutes)),
          ],
        ),
        if (_note.isNotEmpty) T(_note, color: c.danger),
        T(
          onIOS
              ? 'Reminders are planned a week ahead and again each time HYETI opens.'
              : 'Reminders are planned a week ahead, again each time HYETI opens, and after the phone restarts.',
          variant: TextVariant.small,
          dim: true,
        ),
      ],
    );
  }
}

/// A one-time offer on the Calendar: turn reminders on, or say no. Gone once answered either way.
class ReminderOffer extends StatefulWidget {
  const ReminderOffer({super.key});

  /// Whether to show it: reminders were never set up and the question was never answered.
  static bool get due => reminderLead() == null && !appDb.setting('reminder_asked', false);

  @override
  State<ReminderOffer> createState() => _ReminderOfferState();
}

class _ReminderOfferState extends State<ReminderOffer> {
  String _note = '';

  Future<void> _yes() async {
    final ok = await turnOnReminders(10);
    if (!ok) {
      if (mounted) setState(() => _note = _denied);
      return;
    }
    await appDb.setSetting('reminder_asked', true);
  }

  /// One slim row rather than a big card: a bell, the question, "Turn on", and an × that says no.
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
      spacing: Spacing.xs,
      children: [
        Row(
          spacing: Spacing.sm,
          children: [
            Icon(Icons.notifications_active_outlined, color: c.accent, size: 20),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T('Get a reminder before each block?', variant: TextVariant.label, maxLines: 2),
                  T('10 minutes before. Change it in Settings.', variant: TextVariant.small, dim: true, maxLines: 1),
                ],
              ),
            ),
            AppButton('Turn on', small: true, onPressed: _yes),
            Semantics(
              button: true,
              label: 'No thanks',
              excludeSemantics: true,
              child: IconButton(
                onPressed: () => appDb.setSetting('reminder_asked', true),
                icon: Icon(Icons.close, size: 20, color: c.textDim),
                tooltip: 'No thanks',
              ),
            ),
          ],
        ),
        if (_note.isNotEmpty) T(_note, variant: TextVariant.small, color: c.danger),
      ],
    );
  }
}
