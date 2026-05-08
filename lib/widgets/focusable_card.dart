import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_focus.dart';
import '../theme/app_radius.dart';

class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.borderRadius = AppRadius.card,
    this.scale = AppFocus.focusedScale,
    this.selected = false,
    this.decorationBuilder,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final double borderRadius;
  final double scale;
  final bool selected;
  final BoxDecoration Function(bool focused, bool selected)? decorationBuilder;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final decoration =
        widget.decorationBuilder?.call(_focused, widget.selected) ??
        AppFocus.cardDecoration(
          _focused,
          selected: widget.selected,
          radius: widget.borderRadius,
        );
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        // Fix 4: Use a single AnimatedScale instead of AnimatedScale +
        // AnimatedContainer running simultaneously. On a TV home screen with
        // 140+ focusable cards, the double-animation was doubling GPU repaint
        // work on every D-pad focus change. A plain DecoratedBox (no animation)
        // for the border/shadow is cheaper and still looks great.
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          // 120ms feels snappier on TV remote than the default 200ms.
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: DecoratedBox(
            decoration: decoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius - 1),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
