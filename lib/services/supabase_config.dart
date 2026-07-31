import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://cplqrewuoltiechxxtjk.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwbHFyZXd1b2x0aWVjaHh4dGprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwNDg0MDMsImV4cCI6MjA5NjYyNDQwM30.iDypdQt1RpcpffUvtrg_Ykr2tJwdG3CasoHmruTbS-A';

  static SupabaseClient get client => Supabase.instance.client;

  static bool get isAuthenticated {
    try {
      return client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  static String? get currentUserIdOrNull {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static String get currentUserId =>
      currentUserIdOrNull ?? (throw StateError('Not authenticated'));

  static Future<void> init() async {
    try {
      await Supabase.initialize(url: url, publishableKey: anonKey);
    } catch (e) {
      debugPrint('[SupabaseConfig] Initialization error: $e');
    }
  }

  static Future<bool> signInAnonymously() async {
    try {
      final existing = client.auth.currentSession;
      if (existing != null && !existing.isExpired) return true;

      if (existing != null) {
        try {
          final refreshed = await client.auth.refreshSession();
          if (refreshed.session?.user != null &&
              refreshed.session?.isExpired == false) {
            return true;
          }
        } catch (e) {
          debugPrint('[Supabase Auth] Session refresh failed: $e');
        }
      }

      final response = await client.auth.signInAnonymously();
      return response.session?.user != null;
    } catch (e) {
      debugPrint('[Supabase Auth] Anonymous sign-in failed: $e');
      return false;
    }
  }
}
