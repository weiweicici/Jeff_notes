import 'supabase_config.dart';

/// Captures and revalidates the authenticated cloud identity around an async
/// operation. A null capture means no valid session exists; callers must keep
/// local data and skip the cloud operation.
class CloudIdentityGuard {
  static String? capture() => SupabaseConfig.currentUserIdOrNull;

  static bool stillCurrent(String userId) =>
      SupabaseConfig.hasValidSession &&
      SupabaseConfig.currentUserIdOrNull == userId;
}
