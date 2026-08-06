import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps a panel open briefly on first display, then leaves all subsequent
/// expansion/collapse decisions to the user.
class TimedExpansionController extends ChangeNotifier {
  TimedExpansionController({
    bool initiallyExpanded = true,
    Duration initialAutoHideDelay = const Duration(seconds: 30),
  }) : _isExpanded = initiallyExpanded {
    if (initiallyExpanded) {
      _initialAutoHideTimer = Timer(initialAutoHideDelay, _collapseInitially);
    }
  }

  bool _isExpanded;
  Timer? _initialAutoHideTimer;

  bool get isExpanded => _isExpanded;

  void toggleManually() {
    _initialAutoHideTimer?.cancel();
    _initialAutoHideTimer = null;
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void _collapseInitially() {
    _initialAutoHideTimer = null;
    if (!_isExpanded) return;
    _isExpanded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _initialAutoHideTimer?.cancel();
    super.dispose();
  }
}
