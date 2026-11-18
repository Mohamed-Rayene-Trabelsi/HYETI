import 'package:material_ui/material_ui.dart';

import '../countries.dart';
import '../date.dart';
import '../db.dart';
import '../football.dart';
import '../football_pickers.dart';
import '../pickers.dart';
import '../theme.dart';
import '../ui.dart';
import '../update.dart';
import 'calendar.dart';

/// The settings menu: one row per area, each showing what it is set to now and opening its own page.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static void _open(BuildContext context, String title, WidgetBuilder body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsPage(title: title, body: body),
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
          final theme = _themeNames[appDb.setting('theme', 'system')] ?? 'Match phone';
          final paletteId = appDb.setting('palette', 'indigo');
          final palette = paletteId == 'custom'
              ? 'Custom'
              : (palettes.where((p) => p.id == paletteId).firstOrNull?.name ?? 'Indigo');
          final country = appDb.setting('country', '');
          final off = offWeekdays();
          final football = footballPrefs();
          final clubs = football.clubs.length;

          return Screen(
            title: 'Settings',
            onBack: () => Navigator.of(context).pop(),
            children: [
              _MenuGroup(
                children: [
                  _MenuRow(
                    icon: Icons.palette_outlined,
                    tint: c.accent,
                    label: 'Appearance',
                    value: '$theme · $palette',
                    onTap: () => _open(context, 'Appearance', (_) => const _AppearancePage()),
                  ),
                  _MenuRow(
                    icon: Icons.public,
                    tint: const Color(0xFF4FC3F7),
                    label: 'Country and units',
                    value: [
                      if (country.isNotEmpty) country,
                      appDb.setting('currency', r'$'),
                      appDb.setting('weight_unit', 'kg'),
                    ].join(' · '),
                    onTap: () => _open(context, 'Country and units', (_) => const _CountryPage()),
                  ),
                  _MenuRow(
                    icon: Icons.beach_access_outlined,
                    tint: const Color(0xFFE6A23C),
                    label: 'Days off',
                    value: off.isEmpty ? 'None every week' : off.map((d) => weekdays[d]).join(', '),
                    onTap: () => _open(context, 'Days off', (_) => const _DaysOff()),
                  ),
                ],
              ),
              _MenuGroup(
                children: [
                  _MenuRow(
                    icon: Icons.sports_soccer,
                    tint: const Color(0xFF3DBE7F),
                    label: 'Football',
                    value: football.off
                        ? 'Off'
                        : [
                            ?football.nation?.name,
                            if (clubs > 0) '$clubs ${clubs == 1 ? 'club' : 'clubs'}',
                          ].join(' · '),
                    onTap: () => _open(
                      context,
                      'Football',
                      (_) => ListenableBuilder(
                        listenable: appDb,
                        builder: (_, _) => _FootballSettings(prefs: footballPrefs()),
                      ),
                    ),
                  ),
                  _MenuRow(
                    icon: Icons.movie_outlined,
                    tint: const Color(0xFFFF6FAE),
                    label: 'Movie and series data',
                    value: appDb.setting('tmdb_key', '').isNotEmpty ? 'Key saved' : 'Not set up',
                    onTap: () => _open(context, 'Movie and series data', (_) => const KeysForm()),
                  ),
                ],
              ),
              _MenuGroup(
                children: [
                  _MenuRow(
                    icon: Icons.info_outline,
                    tint: c.textDim,
                    label: 'About',
                    value: 'Version $appVersion',
                    onTap: () => _open(context, 'About', (_) => const UpdateCheck()),
                  ),
                  _MenuRow(
                    icon: Icons.delete_outline,
                    tint: c.danger,
                    label: 'Erase all data',
                    labelColor: c.danger,
                    onTap: () => _open(context, 'Erase all data', (_) => const _ErasePage()),
                  ),
                ],
              ),
              const T(
                'Everything is stored on this phone. No account, no sync, no ads.',
                variant: TextVariant.small,
                dim: true,
                align: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

const _themeNames = {'system': 'Match phone', 'light': 'Light', 'dark': 'Dark'};

/// A card of menu rows with hairlines between them.
class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<_MenuRow> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      spacing: 0,
      children: [
        for (final (i, row) in children.indexed) ...[
          if (i > 0) Container(height: 0.5, margin: const EdgeInsets.only(left: 64), color: c.border),
          row,
        ],
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.onTap,
    this.value = '',
    this.labelColor,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: value.isEmpty ? label : '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          tick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            spacing: Spacing.md,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Radii.button - 2),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T(
                      label,
                      variant: TextVariant.label,
                      color: labelColor,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 15),
                    ),
                    if (value.isNotEmpty) T(value, variant: TextVariant.small, dim: true, maxLines: 1),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: c.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// One settings area on a page of its own.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.body});

  final String title;
  final WidgetBuilder body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Screen(
        title: title,
        onBack: () => Navigator.of(context).pop(),
        children: [
          AppCard(children: [body(context)]),
        ],
      ),
    );
  }
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appDb,
      builder: (context, _) => FormColumn(
        children: [
          const T('Light or dark', variant: TextVariant.label),
          Segmented<String>(
            value: appDb.setting('theme', 'system'),
            onChanged: (v) => appDb.setSetting('theme', v),
            options: _themeNames,
          ),
          const T('Colours', variant: TextVariant.label),
          const ThemePicker(),
        ],
      ),
    );
  }
}

class _CountryPage extends StatefulWidget {
  const _CountryPage();

  @override
  State<_CountryPage> createState() => _CountryPageState();
}

class _CountryPageState extends State<_CountryPage> {
  final _currency = TextEditingController(text: appDb.setting('currency', r'$'));

  @override
  void dispose() {
    _currency.dispose();
    super.dispose();
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

  /// The currency is saved as it is typed; an empty box keeps the last one.
  void _currencyEdited(String text) {
    final next = text.trim();
    if (next.isNotEmpty && next != appDb.setting('currency', r'$')) appDb.setSetting('currency', next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appDb,
      builder: (context, _) => FormColumn(
        children: [
          SettingRow(label: 'Country', value: appDb.setting('country', ''), icon: Icons.public, onTap: _chooseCountry),
          Field(
            label: 'Currency',
            controller: _currency,
            hint: r'$',
            capitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: _currencyEdited,
          ),
          const T('Set by your country. Type a symbol or code to use another.', variant: TextVariant.small, dim: true),
          const T('Gym weights', variant: TextVariant.label),
          Segmented<String>(
            value: appDb.setting('weight_unit', 'kg'),
            onChanged: (v) => appDb.setSetting('weight_unit', v),
            options: const {'kg': 'Kilograms', 'lb': 'Pounds'},
          ),
          const T('Weights you already logged keep their numbers.', variant: TextVariant.small, dim: true),
        ],
      ),
    );
  }
}

/// Erasing gets a page of its own, so it can never be tapped by accident from the menu.
class _ErasePage extends StatefulWidget {
  const _ErasePage();

  @override
  State<_ErasePage> createState() => _ErasePageState();
}

class _ErasePageState extends State<_ErasePage> {
  bool _done = false;

  Future<void> _eraseAll() async {
    await appDb.eraseAll();
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_done) return T('Everything was erased.', color: c.success);
    return FormColumn(
      children: [
        T('Erase everything?', variant: TextVariant.heading, color: c.danger),
        const T(
          'Every block, note, sketch, workout, meal, transaction, saved title and setting is removed from this '
          'phone. This cannot be undone.',
          dim: true,
        ),
        AppButton('Erase everything', kind: ButtonKind.danger, icon: Icons.delete_outline, onPressed: _eraseAll),
        AppButton('Keep my data', kind: ButtonKind.soft, onPressed: () => Navigator.of(context).pop()),
      ],
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

  /// The how-to text is long; it is open while the TMDB key is missing, and on request after that.
  late bool _help = _tmdb.text.isEmpty;

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
        const T('Both keys are free and stay on this phone.', dim: true),
        if (!_help)
          AppButton(
            'How to get the keys',
            kind: ButtonKind.plain,
            small: true,
            icon: Icons.help_outline,
            onPressed: () => setState(() => _help = true),
          ),
        if (_help)
          const T(
            'TMDB (lists and release dates): make an account at themoviedb.org, open Settings → API, '
            'request a developer key and copy the “API Key”.\n'
            'OMDb (IMDb ratings, optional): at omdbapi.com choose API Key → Free; the key arrives by email.',
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
    return FormColumn(
      children: [
        Segmented<bool>(
          value: !prefs.off,
          onChanged: (on) => saveFootballPrefs(prefs.copyWith(setUp: true, off: !on)),
          options: const {true: 'I follow football', false: "I don't"},
        ),
        if (!prefs.off) ...[
          Column(
            children: [
              SettingRow(
                label: 'National team',
                value: prefs.nation?.name ?? '',
                onTap: () => openFootballEdit(context, 'nation'),
              ),
              SettingRow(
                label: 'Clubs',
                value: prefs.clubs.map((c) => c.name).join(', '),
                divider: true,
                onTap: () => openFootballEdit(context, 'clubs'),
              ),
              SettingRow(
                label: 'Leagues',
                value: leagues.join(', '),
                divider: true,
                onTap: () => openFootballEdit(context, 'leagues'),
              ),
            ],
          ),
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

/// Which days are off: weekdays that always are, and single dates such as holidays. On a day off the calendar
/// leaves work blocks out.
class _DaysOff extends StatefulWidget {
  const _DaysOff();

  @override
  State<_DaysOff> createState() => _DaysOffState();
}

class _DaysOffState extends State<_DaysOff> with Live {
  List<String> _dates = [];

  @override
  Future<void> load() async {
    final rows = await appDb.query('SELECT date FROM day_offs WHERE date >= ? ORDER BY date', [todayKey()]);
    _dates = [for (final r in rows) r['date'] as String];
  }

  void _toggleWeekday(int day) {
    final days = offWeekdays();
    appDb.setSetting('off_weekdays', days.contains(day) ? (days..remove(day)) : ([...days, day]..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final weekly = offWeekdays();
    return FormColumn(
      children: [
        const T('Every week', variant: TextVariant.label),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final (i, name) in weekdays.indexed)
              AppChip(name, selected: weekly.contains(i), onPressed: () => _toggleWeekday(i)),
          ],
        ),
        const T('Other days off', variant: TextVariant.label),
        if (_dates.isNotEmpty)
          Column(
            children: [
              for (final (i, date) in _dates.indexed)
                ListRow(
                  divider: i > 0,
                  children: [
                    Expanded(child: T('${formatDay(date)} ${date.substring(0, 4)}', maxLines: 1)),
                    Semantics(
                      button: true,
                      label: 'Remove ${formatDay(date)}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          tick();
                          await appDb.run('DELETE FROM day_offs WHERE date = ?', [date]);
                          showUndo(
                            '${formatDay(date)} is a normal day again',
                            () => appDb.run('INSERT OR IGNORE INTO day_offs (date) VALUES (?)', [date]),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(Spacing.xs),
                          child: Icon(Icons.close, size: 20, color: c.textDim),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        DateField(
          label: 'Add a day off',
          value: '',
          onChanged: (date) {
            if (date.isNotEmpty) appDb.run('INSERT OR IGNORE INTO day_offs (date) VALUES (?)', [date]);
          },
        ),
        const T('On a day off, work blocks are left off your calendar.', variant: TextVariant.small, dim: true),
      ],
    );
  }
}
