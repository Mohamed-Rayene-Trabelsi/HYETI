import 'package:material_ui/material_ui.dart';

import 'db.dart';
import 'football.dart';
import 'screens/body.dart';
import 'screens/calendar.dart';
import 'screens/notes.dart';
import 'screens/settings.dart';
import 'screens/wallet.dart';
import 'screens/watch.dart';
import 'theme.dart';
import 'ui.dart';
import 'update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opened before the first frame, so the saved theme is known and never flashes the wrong one.
  appDb = await AppDb.open();
  runApp(const LifeApp(checkForUpdates: true));
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key, this.checkForUpdates = false});

  /// Whether to ask GitHub for a newer release once the app is up. Off in tests.
  final bool checkForUpdates;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appDb,
      builder: (context, _) {
        final choice = appDb.setting<String>('theme', 'system');
        final palette = paletteFor(
          appDb.setting('palette', 'indigo'),
          customAccent: appDb.setting<int?>('custom_accent', null),
          customBase: appDb.setting('custom_base', 'neutral'),
        );
        return MaterialApp(
          title: 'HYETI',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          theme: buildTheme(Brightness.light, palette),
          darkTheme: buildTheme(Brightness.dark, palette),
          themeMode: switch (choice) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          // Touching anything else — a tab, a button, a swipe — puts an undo message away.
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) => dismissUndo(e.position),
            child: child,
          ),
          home: AppTabs(checkForUpdates: checkForUpdates),
          routes: {'/settings': (_) => const SettingsScreen()},
        );
      },
    );
  }
}

class _Tab {
  const _Tab(this.title, this.icon, this.iconActive, this.screen);
  final String title;
  final IconData icon;
  final IconData iconActive;
  final Widget screen;
}

const _tabs = [
  _Tab('Calendar', Icons.calendar_today_outlined, Icons.calendar_today, CalendarScreen()),
  _Tab('Body', Icons.fitness_center_outlined, Icons.fitness_center, BodyScreen()),
  _Tab('Wallet', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, WalletScreen()),
  _Tab('Watch', Icons.movie_outlined, Icons.movie, WatchScreen()),
  _Tab('Notes', Icons.description_outlined, Icons.description, NotesScreen()),
];

/// The five tabs. Swipe sideways or use the bar to move between them.
class AppTabs extends StatefulWidget {
  const AppTabs({super.key, this.checkForUpdates = false});

  final bool checkForUpdates;

  @override
  State<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends State<AppTabs> with WidgetsBindingObserver {
  final _pages = PageController();
  final _scrolls = [for (final _ in _tabs) ScrollController()];
  int _index = 0;

  /// The tab a bar tap is travelling to; pages passed on the way do not count as selected.
  int? _target;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.checkForUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) promptForUpdate(context);
      });
    }
    // Once a day: the coming matches of the national team and clubs followed go on the calendar.
    // Offline, it tries again next time.
    syncFootballCalendar().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    for (final s in _scrolls) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Dates and "now" may have moved on while the app was in the background.
    if (state == AppLifecycleState.resumed) appDb.refresh();
  }

  Future<void> _select(int i) async {
    if (i == _index) {
      // Tapping the tab you are on goes back to the top.
      final scroll = _scrolls[i];
      if (scroll.hasClients && scroll.offset > 0) {
        scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
      return;
    }
    tick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = i;
      _target = i;
    });
    await _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    _target = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnnotatedRegion(
      value: overlayStyle(context),
      // Back from any other tab returns to the first one before leaving the app.
      child: PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(0);
        },
        child: Scaffold(
          body: Column(
            children: [
              // Stays put while the tabs slide underneath it.
              const TopBar(),
              Expanded(
                // The bar already covers the status bar, so the tabs need no top inset.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) {
                      if (_target != null || i == _index) return;
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _index = i);
                    },
                    children: [
                      for (final (i, t) in _tabs.indexed)
                        _KeepAlive(
                          child: PrimaryScrollController(controller: _scrolls[i], child: t.screen),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border, width: 0.5)),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              indicatorShape: buttonShape,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.iconActive), label: t.title),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab's state (scroll position, open sub-tab) while another tab is on screen.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
