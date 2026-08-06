import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps a panel open briefly, then automatically collapses it. Every manual
/// expansion starts a fresh auto-hide countdown.
class TimedExpansionController extends ChangeNotifier {
  TimedExpansionController({
    bool initiallyExpanded = true,
    Duration initialAutoHideDelay = const Duration(seconds: 30),
  }) : _isExpanded = initiallyExpanded,
       _autoHideDelay = initialAutoHideDelay {
    if (initiallyExpanded) _scheduleAutoHide();
  }

  bool _isExpanded;
  final Duration _autoHideDelay;
  Timer? _autoHideTimer;

  bool get isExpanded => _isExpanded;

  void toggleManually() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _scheduleAutoHide();
    } else {
      _cancelAutoHide();
    }
    notifyListeners();
  }

  void _scheduleAutoHide() {
    _cancelAutoHide();
    _autoHideTimer = Timer(_autoHideDelay, _collapse);
  }

  void _cancelAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _collapse() {
    _autoHideTimer = null;
    if (!_isExpanded) return;
    _isExpanded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelAutoHide();
    super.dispose();
  }
}
