/// SG6 (docs/specs/2026-10-05-offline-first-startup-gate.md): the last known
/// capability codes per (userId, organizationId). UX only -- the backend
/// stays the authority (AGENTS.md rule 5).
///
/// A separate interface from LastKnownIdentityStore on purpose: that one has
/// many hand-written test fakes, and capabilities are an optional concern of
/// the same row.
abstract interface class CapabilitySnapshotStore {
  /// The stored codes, or null when nothing is stored for exactly this pair.
  Future<Set<String>?> readCapabilityCodes({
    required String userId,
    required String organizationId,
  });

  /// Stores [codes] only if the stored identity row still belongs to exactly
  /// ([userId], [organizationId]), in one statement. Returns false and writes
  /// nothing otherwise, so a resolve that finishes after a purge cannot
  /// write the set back.
  Future<bool> writeCapabilityCodes({
    required String userId,
    required String organizationId,
    required Set<String> codes,
  });
}
