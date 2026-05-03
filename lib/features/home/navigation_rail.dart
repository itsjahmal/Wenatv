import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class WenaNavigationRail extends StatefulWidget {
  const WenaNavigationRail({super.key, required this.active});

  final String active;

  @override
  State<WenaNavigationRail> createState() => _WenaNavigationRailState();
}

class _WenaNavigationRailState extends State<WenaNavigationRail> {
  late final List<FocusNode> _itemFocusNodes;

  @override
  void initState() {
    super.initState();
    _itemFocusNodes = List.generate(
      _railItems.length,
      (index) => FocusNode(debugLabel: 'nav-${_railItems[index].label}'),
    );
  }

  @override
  void dispose() {
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TvLayout.navRailWidth,
      child: Container(
        width: TvLayout.navRailWidth,
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
              final itemGap = compact ? 8.0 : 11.0;
              final itemHeight = compact ? 38.0 : 42.0;
              return Stack(
                children: [
                  Positioned(
                    top: compact ? 12 : 20,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      width: 44,
                      height: 40,
                      child: Center(
                        child: Text(
                          'W',
                          style: TextStyle(
                            color: WenaTheme.red,
                            fontSize: compact ? 28 : 31,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, compact ? 8 : 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _railItems.length; i++) ...[
                            _RailButton(
                              item: _railItems[i],
                              focusNode: _itemFocusNodes[i],
                              focusNodes: _itemFocusNodes,
                              index: i,
                              active: _railItems[i].label == widget.active,
                              height: itemHeight,
                            ),
                            if (i != _railItems.length - 1)
                              SizedBox(height: itemGap),
                          ],
                        ],
                      ),
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
    required this.focusNode,
    required this.focusNodes,
    required this.index,
    required this.active,
    required this.height,
  });

  final _RailItem item;
  final FocusNode focusNode;
  final List<FocusNode> focusNodes;
  final int index;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: height,
      child: _RailFocusable(
        active: active,
        focusNode: focusNode,
        focusNodes: focusNodes,
        index: index,
        onPressed: () => context.go(item.route),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              Positioned(
                left: 5,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 3.5,
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
            Icon(
              item.icon,
              color: active ? WenaTheme.red : Colors.white,
              size: 20,
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
    required this.focusNode,
    required this.focusNodes,
    required this.index,
    required this.onPressed,
    required this.child,
  });

  final bool active;
  final FocusNode focusNode;
  final List<FocusNode> focusNodes;
  final int index;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_RailFocusable> createState() => _RailFocusableState();
}

class _RailFocusableState extends State<_RailFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && _isActivationKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final next = (widget.index + 1).clamp(
            0,
            widget.focusNodes.length - 1,
          );
          widget.focusNodes[next].requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final previous = (widget.index - 1).clamp(
            0,
            widget.focusNodes.length - 1,
          );
          widget.focusNodes[previous].requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          FocusScope.of(context).focusInDirection(TraversalDirection.right);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.018 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: .075)
                  : widget.active
                  ? WenaTheme.red.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
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

const _railItems = [
  _RailItem('Search', Icons.search, '/search'),
  _RailItem('Home', Icons.home_outlined, '/'),
  _RailItem('Movies', Icons.movie_creation_outlined, '/movies'),
  _RailItem('Series', Icons.live_tv_outlined, '/tv'),
  _RailItem('Trending', Icons.trending_up, '/trending'),
  _RailItem('Watchlist', Icons.bookmark_add_outlined, '/watchlist'),
  _RailItem('Settings', Icons.settings_outlined, '/settings'),
];

bool _isActivationKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;
}
