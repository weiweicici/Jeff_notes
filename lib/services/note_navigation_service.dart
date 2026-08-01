import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/note_detail_screen.dart';

/// Owns navigation for automatically surfaced or manually resumed notes.
///
/// Keeping one managed note route prevents consecutive recording completions
/// from stacking several document viewers on top of the recording screen.
class NoteNavigationService extends NavigatorObserver {
  NoteNavigationService._();

  static final NoteNavigationService instance = NoteNavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const String _managedRouteName = '/managed-note-detail';
  Route<dynamic>? _managedRoute;

  bool _isManaged(Route<dynamic>? route) =>
      route?.settings.name == _managedRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isManaged(route)) _managedRoute = route;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _managedRoute)) _managedRoute = null;
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _managedRoute)) _managedRoute = null;
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, _managedRoute)) _managedRoute = null;
    if (_isManaged(newRoute)) _managedRoute = newRoute;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  Future<bool> openNote({
    required String path,
    required String documentId,
  }) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return false;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;

    final route = MaterialPageRoute<void>(
      settings: RouteSettings(name: _managedRouteName, arguments: documentId),
      builder: (_) => NoteDetailScreen(file: file),
    );

    if (_managedRoute == null) {
      await navigator.push<void>(route);
    } else {
      // Remove any child page opened from the current managed note, then
      // replace the note itself so Back always returns to the recording UI.
      navigator.popUntil(
        (candidate) => identical(candidate, _managedRoute) || candidate.isFirst,
      );
      await navigator.pushReplacement<void, void>(route);
    }
    return true;
  }
}
