import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browse/browse_providers.dart';
import '../browse/live_screen.dart';
import '../browse/search_screen.dart';
import '../browse/series_screen.dart';
import '../browse/vod_screen.dart';
import '../favorites/favorites_screen.dart';
import '../iptv/models.dart';
import '../profiles/profile_controller.dart';
import '../settings/settings_screen.dart';
import '../sources/source_list_screen.dart';
import '../sources/source_repository.dart';

/// Authenticated home: bottom-nav shell. Live tab is built in this task; VOD /
/// Series / Search / Settings tabs are filled by later tasks (placeholders for
/// now). Auto-selects the only source, or prompts to add/pick one.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  static const _tabCount = 4;

  /// Separate focus scopes for the tab body and the bottom bar so we can move
  /// focus deterministically between them with the remote (directional focus is
  /// otherwise confined within a scope, which is why "down" never reached the
  /// bottom bar before).
  final FocusScopeNode _bodyScope = FocusScopeNode(debugLabel: 'tabBody');
  final FocusScopeNode _bottomScope = FocusScopeNode(debugLabel: 'bottomBar');
  final FocusScopeNode _topScope = FocusScopeNode(debugLabel: 'topBar');

  @override
  void dispose() {
    _bodyScope.dispose();
    _bottomScope.dispose();
    _topScope.dispose();
    super.dispose();
  }

  /// Move focus from the tab content onto the bottom navigation bar.
  void focusBottomBar() => _bottomScope.requestFocus();

  /// Move focus onto the app-bar action buttons (reload / favorites / settings).
  void focusTopBar() => _topScope.requestFocus();

  /// Move focus back into the tab content (restores the last-focused tile).
  void focusBody() => _bodyScope.requestFocus();

  /// The drill-in category provider for the active tab (null for Search).
  StateProvider<Category?>? _activeCategoryProvider() {
    switch (_index) {
      case 0:
        return liveSelectedCategoryProvider;
      case 1:
        return vodSelectedCategoryProvider;
      case 2:
        return seriesSelectedCategoryProvider;
      default:
        return null;
    }
  }

  /// Switch to tab [i] (wrapping around) and move focus into its content. Used
  /// by the directional-wrap action when the remote hits a left/right edge.
  void switchTab(int i) {
    final ni = ((i % _tabCount) + _tabCount) % _tabCount;
    if (ni == _index) return;
    setState(() => _index = ni);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bodyScope.nextFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);
    final active = ref.watch(activeSourceProvider);

    // Auto-select when there is exactly one source and none active yet.
    ref.listen(sourceListProvider, (_, next) {
      next.whenData((sources) {
        final current = ref.read(activeSourceProvider);
        if (current == null && sources.length == 1) {
          ref.read(activeSourceProvider.notifier).state = sources.first;
        }
      });
    });

    // Initialise the active profile to the first one once profiles load.
    ref.listen(profilesProvider, (_, next) {
      next.whenData((profiles) {
        if (ref.read(activeProfileIdProvider) == null && profiles.isNotEmpty) {
          ref.read(activeProfileIdProvider.notifier).state = profiles.first.id;
        }
      });
    });
    ref.watch(profilesProvider); // ensure default profile is created

    return sourcesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur: $e'))),
      data: (sources) {
        if (sources.isEmpty) {
          // No source yet -> send the user to the source list (add screen).
          return const SourceListScreen();
        }
        if (active == null) {
          // Multiple sources, none chosen -> let the user pick.
          return SourceListScreen(
            onSelect: (s) => ref.read(activeSourceProvider.notifier).state = s,
          );
        }
        return _shell(context, sources.length);
      },
    );
  }

  Widget _shell(BuildContext context, int sourceCount) {
    final tabs = <Widget>[
      const LiveScreen(),
      const VodScreen(),
      const SeriesScreen(),
      const SearchScreen(),
    ];
    final refreshing = ref.watch(catalogRefreshProvider);
    final activeCatProv = _activeCategoryProvider();
    final hasDrill = activeCatProv != null && ref.watch(activeCatProv) != null;
    return PopScope(
      // When drilled into a category, Back returns to the category list instead
      // of leaving the app; at a tab root, Back pops normally.
      canPop: !hasDrill,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (activeCatProv != null) {
          ref.read(activeCatProv.notifier).state = null;
        }
      },
      child: Actions(
        // Remote edge handling for the whole shell: left/right at a row edge
        // wraps to the prev/next tab; down from the last row jumps to the bottom
        // bar; up from the bottom bar returns to the tab content.
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: _TabWrapDirectionalAction(this),
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Deko IPTV'),
            actions: [
              FocusScope(
                node: _topScope,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: refreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: 'Recharger le catalogue',
                      onPressed: refreshing
                          ? null
                          : () => ref
                                .read(catalogRefreshProvider.notifier)
                                .refresh(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.star_border),
                      tooltip: 'Favoris',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FavoritesScreen(),
                        ),
                      ),
                    ),
                    if (sourceCount > 1)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz),
                        tooltip: 'Changer de source',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SourceListScreen(
                              onSelect: (s) {
                                ref.read(activeSourceProvider.notifier).state =
                                    s;
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      key: const Key('settingsButton'),
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Réglages',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: FocusScope(
            node: _bodyScope,
            child: IndexedStack(
              index: _index,
              // Exclude non-visible tabs from focus so the remote can't land on
              // an offstage tab's tiles.
              children: [
                for (var i = 0; i < tabs.length; i++)
                  ExcludeFocus(excluding: i != _index, child: tabs[i]),
              ],
            ),
          ),
          bottomNavigationBar: FocusScope(
            node: _bottomScope,
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.live_tv), label: 'TV'),
                NavigationDestination(
                  icon: Icon(Icons.movie_outlined),
                  label: 'Films',
                ),
                NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  label: 'Séries',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Recherche',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Overrides directional focus to bridge the tab content and the bottom bar
/// (which live in separate focus scopes) and to wrap left/right between tabs:
///   • in the content: down at the last row -> bottom bar; left/right at a row
///     edge -> previous/next tab; otherwise move within the grid.
///   • on the bottom bar: up -> back into the content; left/right -> move
///     across destinations.
class _TabWrapDirectionalAction extends Action<DirectionalFocusIntent> {
  _TabWrapDirectionalAction(this._state);
  final _HomeShellState _state;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final dir = intent.direction;
    final primary = FocusManager.instance.primaryFocus;

    // Focus on the app bar: down returns to the content; left/right move across
    // the action buttons.
    if (_state._topScope.hasFocus) {
      if (dir == TraversalDirection.down) {
        _state.focusBody();
      } else {
        primary?.focusInDirection(dir);
      }
      return;
    }

    // Focus currently on the bottom bar.
    if (_state._bottomScope.hasFocus) {
      if (dir == TraversalDirection.up) {
        _state.focusBody();
      } else {
        primary?.focusInDirection(dir);
      }
      return;
    }

    // Focus in the tab content.
    if (_state._bodyScope.hasFocus) {
      final moved = primary?.focusInDirection(dir) ?? false;
      if (moved) return;
      switch (dir) {
        case TraversalDirection.right:
          _state.switchTab(_state._index + 1);
          break;
        case TraversalDirection.left:
          _state.switchTab(_state._index - 1);
          break;
        case TraversalDirection.down:
          _state.focusBottomBar();
          break;
        case TraversalDirection.up:
          _state.focusTopBar();
          break;
      }
      return;
    }

    // Elsewhere: default behavior.
    primary?.focusInDirection(dir);
  }
}
