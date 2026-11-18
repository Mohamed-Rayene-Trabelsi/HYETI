import 'package:material_ui/material_ui.dart';

import '../countries.dart';
import '../db.dart';
import '../football.dart';
import '../football_pickers.dart';
import '../theme.dart';
import '../ui.dart';
import '../update.dart';

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

  void _chooseCountry() {
    showSheet(
      context,
      title: 'Country',
      builder: (sheet) => _CountryPicker(
        selected: appDb.setting('country', ''),
        onPick: (name, currency) async {
          Navigator.pop(sheet);
          _currency.text = currency;
          await appDb.setSetting('country', name);
          await appDb.setSetting('currency', currency);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: ListenableBuilder(
        listenable: appDb,
        builder: (context, _) {
          final currency = appDb.setting('currency', r'$');
          final country = appDb.setting('country', '');
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
                title: 'Country and units',
                children: [
                  AppCard(
                    children: [
                      const T('Country', variant: TextVariant.label),
                      AppButton(
                        country.isEmpty ? 'Choose a country' : country,
                        kind: ButtonKind.soft,
                        icon: Icons.public,
                        onPressed: _chooseCountry,
                      ),
                      const T(
                        'Choosing a country sets the currency below; you can still type another.',
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
                      const SizedBox(height: Spacing.xs),
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
                    ],
                  ),
                ],
              ),
              Section(
                title: 'Football',
                children: [
                  AppCard(children: [_FootballSettings(prefs: footballPrefs())]),
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
              const Section(
                title: 'About',
                children: [
                  AppCard(children: [UpdateCheck()]),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The installed version, and a button that looks for a newer one.
class UpdateCheck extends StatefulWidget {
  const UpdateCheck({super.key});

  @override
  State<UpdateCheck> createState() => _UpdateCheckState();
}

enum _Check { idle, busy, latest, failed }

class _UpdateCheckState extends State<UpdateCheck> {
  _Check _state = _Check.idle;

  Future<void> _check() async {
    setState(() => _state = _Check.busy);
    try {
      final release = await fetchLatestRelease();
      if (!mounted) return;
      final newer = isNewer(release.version, appVersion);
      setState(() => _state = newer ? _Check.idle : _Check.latest);
      if (newer) showUpdateSheet(context, release);
    } catch (_) {
      if (mounted) setState(() => _state = _Check.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormColumn(
      children: [
        const T('HYETI version $appVersion', variant: TextVariant.label),
        if (_state == _Check.latest) T('This is the newest version.', color: c.success),
        if (_state == _Check.failed) const T('Could not check. Is the phone online?', dim: true),
        AppButton(
          _state == _Check.busy ? 'Checking…' : 'Check for updates',
          kind: ButtonKind.soft,
          icon: Icons.system_update,
          onPressed: _state == _Check.busy ? null : _check,
        ),
      ],
    );
  }
}

/// A searchable list of countries, each with the currency it brings.
class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.selected, required this.onPick});

  final String selected;
  final void Function(String name, String currency) onPick;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final words = _search.text.trim().toLowerCase();
    final shown = [
      for (final country in countries)
        if (country.$1.toLowerCase().contains(words)) country,
    ];
    return FormColumn(
      children: [
        Field(
          controller: _search,
          icon: Icons.search,
          hint: 'Search countries',
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
        ),
        if (shown.isEmpty) const T('No country by that name. You can type the currency in settings.', dim: true),
        Column(
          children: [
            for (final (i, (name, currency)) in shown.indexed)
              ListRow(
                divider: i > 0,
                onTap: () {
                  tick();
                  widget.onPick(name, currency);
                },
                children: [
                  Expanded(child: T(name, maxLines: 1)),
                  T(currency, variant: TextVariant.label, dim: true),
                  if (name == widget.selected) Icon(Icons.check, size: 18, color: c.accent),
                ],
              ),
          ],
        ),
      ],
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
                        borderRadius: BorderRadius.circular(Radii.button),
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
                borderRadius: BorderRadius.circular(Radii.button),
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

/// What football is followed. The Football tab itself has no filters; this is where it is changed.
class _FootballSettings extends StatelessWidget {
  const _FootballSettings({required this.prefs});

  final FootballPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final leagues = [for (final id in prefs.leagues) ?topLeagues[id]];
    Widget part(String label, String value, String empty, String key) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.xs,
      children: [
        T(label, variant: TextVariant.label),
        AppButton(
          value.isEmpty ? empty : value,
          kind: ButtonKind.soft,
          onPressed: () => openFootballEdit(context, key),
        ),
      ],
    );
    return FormColumn(
      children: [
        Segmented<bool>(
          value: !prefs.off,
          onChanged: (on) => saveFootballPrefs(prefs.copyWith(setUp: true, off: !on)),
          options: const {true: 'I follow football', false: "I don't"},
        ),
        if (!prefs.off) ...[
          part('Your country', prefs.nation?.name ?? '', 'Choose your national team', 'nation'),
          part('Favourite clubs', prefs.clubs.map((c) => c.name).join(', '), 'Choose clubs', 'clubs'),
          part('Leagues', leagues.join(', '), 'Choose leagues', 'leagues'),
          const T(
            'Matches of your country and clubs go on your calendar as they come within two weeks. '
            'Only what you follow is downloaded.',
            variant: TextVariant.small,
            dim: true,
          ),
        ] else
          const T('The Football tab is hidden from Watch.', variant: TextVariant.small, dim: true),
      ],
    );
  }
}
