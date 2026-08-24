import 'package:supabase_flutter/supabase_flutter.dart';

/// True when [error] is a PostgREST error the server can only ever return
/// for one reason: it authenticated the caller and the caller does not have
/// the right to perform the write. This is permanent for the current
/// identity -- retrying the exact same request will never succeed.
///
/// Deliberately narrow: PostgreSQL code `42501`, HTTP `403`, or the
/// PostgreSQL error text `permission denied for ...` (table/schema/
/// function). The message match is anchored to that full phrase rather
/// than a bare `permission denied` substring, so an unrelated
/// `RAISE EXCEPTION` that happens to quote those two words in its own free
/// text is not misclassified as permanently unauthorized.
///
/// Deliberately does NOT fold in `401` or `AuthException`, unlike
/// `SongCatalogController._isAuthorizationFailure`. That controller-level
/// classifier folds `401` in because the decision it feeds -- fall back to
/// the cached organization id -- is the same whether the failure is
/// transient or permanent. Here, in the mutation-sync repositories, treating
/// `401` as permanent would discard the user's queued work on an ordinary
/// token expiry (spec D5.6): a missing/malformed/expired token can succeed
/// again after re-authentication, so it must stay retryable. Do not "finish
/// the job" by merging that third call site into this helper -- keeping
/// them separate is the point, not an oversight.
///
/// Callers keep their own domain-specific message check (e.g.
/// `song_write_not_authorized`, `not_authorized`) at their own call site --
/// this helper only covers the two checks both repositories duplicated.
bool isPermanentAuthorizationDenial(PostgrestException error) {
  final message = error.message.toLowerCase();
  return error.code == '42501' ||
      error.code == '403' ||
      message.contains('permission denied for');
}
