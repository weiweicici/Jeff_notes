import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://cplqrewuoltiechxxtjk.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwbHFyZXd1b2x0aWVjaHh4dGprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwNDg0MDMsImV4cCI6MjA5NjYyNDQwM30.iDypdQt1RpcpffUvtrg_Ykr2tJwdG3CasoHmruTbS-A';

  static SupabaseClient get client => Supabase.instance.client;

  static String get currentUserId =>
      client.auth.currentUser?.id ?? (throw StateError('Not authenticated to Supabase'));

  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static Future<void> signInAnonymously() async {
    try {
      final response = await client.auth.signInAnonymously();
      // ignore: avoid_print
      print('[Supabase Auth] Signed in as: ${response.session?.user.id}');
    } catch (e) {
      // ignore: avoid_print
      print('[Supabase Auth] Anonymous sign-in failed: $e');
    }
  }
}
