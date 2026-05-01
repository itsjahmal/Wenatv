import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class WenaNavigationRail extends StatelessWidget {
  const WenaNavigationRail({super.key, required this.active});

  final String active;

  @override
  Widget build(BuildContext context) {
    final items = [
      _RailItem('Search', Icons.search, '/search'),
      _RailItem('Home', Icons.home_outlined, '/'),
      _RailItem('Browse', Icons.movie_creation_outlined, '/movies'),
      _RailItem('TV Shows', Icons.live_tv_outlined, '/tv'),
      _RailItem('Trending', Icons.trending_up, '/trending'),
      _RailItem('My List', Icons.bookmark_border, '/watchlist'),
      _RailItem('Settings', Icons.settings_outlined, '/settings'),
    ];
    return SizedBox(
      width: TvLayout.navRailWidth,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: .08)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .55),
              blurRadius: 24,
              offset: const Offset(10, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 650;
              final topGap = compact ? 12.0 : 20.0;
              final logoGap = compact ? 12.0 : 18.0;
              final itemGap = compact ? 3.0 : 5.0;
              final itemHeight = compact ? 45.0 : 49.0;
              return Column(
                children: [
                  SizedBox(height: topGap),
                  Container(
                    width: 48,
                    height: 42,
                    alignment: Alignment.center,
                    child: const Text(
                      'W',
                      style: TextStyle(
                        color: WenaTheme.red,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        height: 1,
                      ),
                    ),
                  ),
                  SizedBox(height: logoGap),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => SizedBox(height: itemGap),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Center(
                          child: _RailButton(
                            item: item,
                            active: item.label == active,
                            height: itemHeight,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.active,
    required this.height,
  });

  final _RailItem item;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: height,
      child: _RailFocusable(
        active: active,
        onPressed: () => context.go(item.route),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              Positioned(
                left: 1,
                top: 11,
                bottom: 11,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: WenaTheme.red,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: WenaTheme.red.withValues(alpha: .65),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  color: active ? WenaTheme.red : Colors.white,
                  size: 22,
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? WenaTheme.red : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RailFocusable extends StatefulWidget {
  const _RailFocusable({
    required this.active,
    required this.onPressed,
    required this.child,
  });

  final bool active;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_RailFocusable> createState() => _RailFocusableState();
}

class _RailFocusableState extends State<_RailFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.025 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: .08)
                  : widget.active
                  ? WenaTheme.red.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? WenaTheme.red
                    : widget.active
                    ? WenaTheme.red.withValues(alpha: .35)
                    : Colors.transparent,
                width: _focused ? 1.4 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: WenaTheme.red.withValues(alpha: .24),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RailItem {
  const _RailItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}
