import 'package:flutter/material.dart';

class _PageTurnGestureCoordinator {
  final Set<int> ignoredPointers = {};

  void ignore(int pointer) => ignoredPointers.add(pointer);
  bool consumeIgnored(int pointer) => ignoredPointers.remove(pointer);
}

class _PageTurnGestureScope extends InheritedWidget {
  const _PageTurnGestureScope({
    required this.coordinator,
    required super.child,
  });

  final _PageTurnGestureCoordinator coordinator;

  static _PageTurnGestureCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PageTurnGestureScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(_PageTurnGestureScope oldWidget) => false;
}

/// Marks buttons or other controls embedded in a document as non-page-turning.
class TapPageTurnIgnore extends StatelessWidget {
  const TapPageTurnIgnore({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final coordinator = _PageTurnGestureScope.maybeOf(context);
    if (coordinator == null) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => coordinator.ignore(event.pointer),
      child: child,
    );
  }
}

/// Adds reader-style page turning to a scrollable document.
///
/// A short tap in the upper half moves back by [pageFraction] of the viewport;
/// a short tap in the lower half moves forward. Dragging and long-press text
/// selection remain intact. Embedded controls should use [TapPageTurnIgnore].
class TapPageTurnRegion extends StatefulWidget {
  const TapPageTurnRegion({
    super.key,
    required this.controller,
    required this.child,
    this.pageFraction = 0.88,
    this.duration = const Duration(milliseconds: 180),
    this.onPageChanged,
  });

  final ScrollController controller;
  final Widget child;
  final double pageFraction;
  final Duration duration;
  final VoidCallback? onPageChanged;

  @override
  State<TapPageTurnRegion> createState() => _TapPageTurnRegionState();
}

class _TapPageTurnRegionState extends State<TapPageTurnRegion> {
  final _coordinator = _PageTurnGestureCoordinator();
  final Map<int, (Offset, DateTime)> _pointerStarts = {};

  Future<void> _turnPage({required bool forward}) async {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final delta = position.viewportDimension * widget.pageFraction;
    final target = (position.pixels + (forward ? delta : -delta)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;

    await widget.controller.animateTo(
      target,
      duration: widget.duration,
      curve: Curves.easeOut,
    );
    // A selectable child can cancel this animation while resolving its caret.
    // A page tap has already been positively identified here, so make the
    // requested page boundary authoritative after competing scroll activity.
    if (!mounted || !widget.controller.hasClients) return;
    widget.controller.jumpTo(target);
    widget.onPageChanged?.call();
  }

  void _handlePointerUp(PointerUpEvent event, double viewportHeight) {
    final start = _pointerStarts.remove(event.pointer);
    if (_coordinator.consumeIgnored(event.pointer) || start == null) return;
    final travel = (event.localPosition - start.$1).distance;
    final elapsed = DateTime.now().difference(start.$2);
    if (travel > 10 || elapsed > const Duration(milliseconds: 400)) return;

    final forward = event.localPosition.dy >= viewportHeight / 2;
    // SelectableText resolves its tap and may request bring-into-view after
    // pointer-up (sometimes in the following frame). Let that settle before
    // starting the page animation, otherwise it can reset the new offset.
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _turnPage(forward: forward);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _PageTurnGestureScope(
        coordinator: _coordinator,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _pointerStarts[event.pointer] = (
              event.localPosition,
              DateTime.now(),
            );
          },
          onPointerUp: (event) =>
              _handlePointerUp(event, constraints.maxHeight),
          onPointerCancel: (event) {
            _pointerStarts.remove(event.pointer);
            _coordinator.consumeIgnored(event.pointer);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
