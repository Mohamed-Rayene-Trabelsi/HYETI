import 'package:material_ui/material_ui.dart';

import '../db.dart';
import '../theme.dart';
import '../ui.dart';

const appVersion = '1.0.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _Erase { idle, confirm, done }

class _SettingsScreenState extends State<SettingsScreen> {
  final _currency = TextEditingController(text: appDb.setting('currency', r'$'));
  _Erase _erase = _Erase.idle;

  @override
  void dispose() {
    _currency.dispose();
    super.dispose();
  }

  Future<void> _eraseAll() async {
    await appDb.eraseAll();
    _currency.text = r'$';
    if (mounted) setState(() => _erase = _Erase.done);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: ListenableBuilder(
        listenable: appDb,
        builder: (context, _) {
          final currency = appDb.setting('currency', r'$');
          return Screen(
            title: 'Settings',
            subtitle: 'Everything is stored on this phone',
            onBack: () => Navigator.of(context).pop(),
            children: [
              Section(
                title: 'Appearance',
                children: [
                  AppCard(
                    children: [
                      const T('Light or dark', variant: TextVariant.label),
                      Segmented<String>(
                        value: appDb.setting('theme', 'system'),
                        onChanged: (v) => appDb.setSetting('theme', v),
                        options: const {'system': 'Match phone', 'light': 'Light', 'dark': 'Dark'},
                      ),
                      const SizedBox(height: Spacing.xs),
                      const T('Colours', variant: TextVariant.label),
                      const ThemePicker(),
                    ],
                  ),
                ],
              ),
              Section(
                title: 'Calendar',
                children: [
                  AppCard(
                    children: [
                      const T('Week starts on', variant: TextVariant.label),
                      Segmented<String>(
                        value: appDb.setting('week_start', 'mon'),
                        onChanged: (v) => appDb.setSetting('week_start', v),
                        options: const {'mon': 'Monday', 'sun': 'Sunday'},
                      ),
                    ],
                  ),
                ],
              ),
              Section(
                title: 'Units',
                children: [
                  AppCard(
                    children: [
                      const T('Gym weights', variant: TextVariant.label),
                      Segmented<String>(
                        value: appDb.setting('weight_unit', 'kg'),
                        onChanged: (v) => appDb.setSetting('weight_unit', v),
                        options: const {'kg': 'Kilograms', 'lb': 'Pounds'},
                      ),
                      const T(
                        'Changes the label only. Weights you already logged are not converted.',
                        variant: TextVariant.small,
                        dim: true,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: Spacing.sm,
                        children: [
                          Expanded(
                            child: Field(
                              label: 'Currency symbol or code',
                              controller: _currency,
                              hint: r'$',
                              capitalization: TextCapitalization.characters,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (_currency.text.trim() != currency)
                            AppButton(
                              'Save',
                              small: true,
                              onPressed: () async {
                                final next = _currency.text.trim().isEmpty ? r'$' : _currency.text.trim();
                                _currency.text = next;
                                await appDb.setSetting('currency', next);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const Section(
                title: 'Movie and series data',
                children: [
                  AppCard(children: [KeysForm()]),
                ],
              ),
              Section(
                title: 'Your data',
                children: [
                  AppCard(
                    children: [
                      const T(
                        'Erasing removes every block, note, workout, meal, transaction, saved title and setting '
                        'from this phone. It cannot be undone.',
                        dim: true,
                      ),
                      if (_erase == _Erase.done) T('Everything was erased.', color: c.success),
                      if (_erase == _Erase.confirm)
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            AppButton('Yes, erase everything', kind: ButtonKind.danger, onPressed: _eraseAll),
                            AppButton(
                              'Cancel',
                              kind: ButtonKind.soft,
                              onPressed: () => setState(() => _erase = _Erase.idle),
                            ),
                          ],
                        )
                      else
                        AppButton(
                          'Erase all data',
                          kind: ButtonKind.danger,
                          onPressed: () => setState(() => _erase = _Erase.confirm),
                        ),
                    ],
                  ),
                ],
              ),
              const T('Version $appVersion', variant: TextVariant.small, dim: true, align: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}

/// The colour themes as tappable previews, plus a custom one built from an accent and a background.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brightness = Theme.of(context).brightness;
    final selected = appDb.setting('palette', 'indigo');
    final customAccent = Color(appDb.setting<int?>('custom_accent', null) ?? accentSwatches.first.toARGB32());
    final customBase = appDb.setting('custom_base', 'neutral');
    final choices = [...palettes, customPalette(customAccent, customBase)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.md,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const perRow = 4, gap = Spacing.sm;
            final width = (box.maxWidth - gap * (perRow - 1)) / perRow - 0.01;
            return Wrap(
              spacing: gap,
              runSpacing: Spacing.md,
              children: [
                for (final p in choices)
                  SizedBox(
                    width: width,
                    child: _ThemeTile(
                      palette: p,
                      brightness: brightness,
                      selected: p.id == selected,
                      onTap: () {
                        tick();
                        appDb.setSetting('palette', p.id);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        if (selected == 'custom') ...[
          const T('Accent colour', variant: TextVariant.label, dim: true),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.md,
            children: [
              for (final swatch in accentSwatches)
                Semantics(
                  button: true,
                  selected: swatch.toARGB32() == customAccent.toARGB32(),
                  label: 'Accent colour',
                  child: GestureDetector(
                    onTap: () {
                      tick();
                      appDb.setSetting('custom_accent', swatch.toARGB32());
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: swatch.toARGB32() == customAccent.toARGB32() ? c.text : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: swatch.toARGB32() == customAccent.toARGB32()
                          ? const Icon(Icons.check, size: 18, color: Color(0xFF0C0D10))
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const T('Dark background', variant: TextVariant.label, dim: true),
          Segmented<String>(
            value: customBase,
            onChanged: (v) => appDb.setSetting('custom_base', v),
            options: customBases,
          ),
        ],
      ],
    );
  }
}

/// A small preview of a theme: its background, a card, and its accent.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.palette, required this.brightness, required this.selected, required this.onTap});

  final Palette palette;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = brightness == Brightness.dark ? palette.dark : palette.light;
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} theme',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          spacing: 6,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 58,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.background,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: selected ? c.accent : c.border, width: selected ? 2.5 : 1),
              ),
              child: Row(
                spacing: 6,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                    child: palette.id == 'custom' ? Icon(Icons.tune, size: 12, color: t.background) : null,
                  ),
                ],
              ),
            ),
            T(
              palette.name,
              variant: TextVariant.small,
              color: selected ? c.text : c.textDim,
              align: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the two free keys for movie and series data are pasted in.
class KeysForm extends StatefulWidget {
  const KeysForm({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<KeysForm> createState() => _KeysFormState();
}

class _KeysFormState extends State<KeysForm> {
  final _tmdb = TextEditingController(text: appDb.setting('tmdb_key', ''));
  final _omdb = TextEditingController(text: appDb.setting('omdb_key', ''));
  bool _saved = false;

  @override
  void dispose() {
    _tmdb.dispose();
    _omdb.dispose();
    super.dispose();
  }

  void _edited(String _) {
    if (_saved) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        const T(
          'Both keys are free and stay on this phone. They are only sent to the service they belong to.',
          dim: true,
        ),
        const T('1. TMDB — hot lists and release dates', variant: TextVariant.label),
        const T(
          'Create an account at themoviedb.org, open Settings → API, request a developer key, '
          'then copy the “API Key”.',
          variant: TextVariant.small,
          dim: true,
        ),
        Field(
          label: 'TMDB key',
          controller: _tmdb,
          hint: 'Paste here',
          capitalization: TextCapitalization.none,
          autocorrect: false,
          onChanged: _edited,
        ),
        const T('2. OMDb — IMDb ratings', variant: TextVariant.label),
        const T(
          'Go to omdbapi.com, choose API Key → Free, and the key arrives by email. Free keys allow 1,000 '
          'lookups a day; ratings are remembered for a week to stay well under that.',
          variant: TextVariant.small,
          dim: true,
        ),
        Field(
          label: 'OMDb key (optional)',
          controller: _omdb,
          hint: 'Paste here',
          capitalization: TextCapitalization.none,
          autocorrect: false,
          onChanged: _edited,
        ),
        AppButton(
          _saved ? 'Saved ✓' : 'Save keys',
          kind: _saved ? ButtonKind.soft : ButtonKind.primary,
          onPressed: () async {
            await appDb.setSetting('tmdb_key', _tmdb.text.trim());
            await appDb.setSetting('omdb_key', _omdb.text.trim());
            if (!mounted) return;
            setState(() => _saved = true);
            widget.onSaved?.call();
          },
        ),
      ],
    );
  }
}
