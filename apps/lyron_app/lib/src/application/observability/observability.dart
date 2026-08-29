/// Backend-agnostic status for a completed span. Named after the W3C/OTel
/// concept, not Sentry's `SpanStatus` type, so a future OpenTelemetry
/// adapter maps onto the same four values without a Sentry-specific name
/// leaking into application code.
enum ObservabilitySpanStatus { ok, cancelled, internalError, unknown }

enum BreadcrumbLevel { debug, info, warning, error }

/// A first-party tracing/error-reporting abstraction. Application code
/// depends only on this interface, never on the Sentry API directly, so a
/// future OpenTelemetry adapter can be substituted without touching call
/// sites. See docs/specs/2026-08-28-observability-foundation.md and
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md for
/// the full design rationale, including why span propagation happens
/// through a dedicated Dart Zone value rather than Sentry's own ambient
/// scope.
abstract class Observability {
  /// Runs [body] as a span named [name] with operation [operation]. If
  /// there is already an active span in the current Zone, the new span is
  /// its child; otherwise it starts a new root trace. The span finishes
  /// automatically when [body] completes or throws; on throw,
  /// [ObservabilitySpanStatus.internalError] is set before the exception
  /// is rethrown unmodified. [body] runs inside a new Zone in which this
  /// span is the ambient [currentSpan]/[currentTraceParent] for its
  /// duration -- including for code with no direct span reference, called
  /// deep inside [body]'s call stack.
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  });

  /// The active span in the current Zone. Never null -- resolves to a
  /// [NoopObservabilitySpan] when nothing is active, so callers never need
  /// to branch on whether tracing is active.
  ObservabilitySpan get currentSpan;

  /// W3C `traceparent` header value for the current span, or null if there
  /// is no active span.
  String? get currentTraceParent;

  /// Reports a handled error, explicitly linked to the current span.
  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  });

  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  });

  /// [userId] and [organizationId] must be pseudonymized identifiers
  /// (Supabase UUIDs) -- never an email address or display name.
  void setUserContext({required String userId, String? organizationId});

  void clearUserContext();
}

abstract class ObservabilitySpan {
  /// A non-ambient nested span: does not enter a new Zone, so it does not
  /// become [Observability.currentSpan] for anything else. Prefer
  /// [Observability.runInSpan] unless you specifically want a nested span
  /// that stays invisible to ambient lookups.
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  });

  void setData(String key, Object? value);
  void setStatus(ObservabilitySpanStatus status);
  Future<void> finish();
}

class NoopObservability implements Observability {
  const NoopObservability();

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    return body(const NoopObservabilitySpan());
  }

  @override
  ObservabilitySpan get currentSpan => const NoopObservabilitySpan();

  @override
  String? get currentTraceParent => null;

  @override
  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  }) {}

  @override
  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  }) {}

  @override
  void setUserContext({required String userId, String? organizationId}) {}

  @override
  void clearUserContext() {}
}

class NoopObservabilitySpan implements ObservabilitySpan {
  const NoopObservabilitySpan();

  @override
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  }) => const NoopObservabilitySpan();

  @override
  void setData(String key, Object? value) {}

  @override
  void setStatus(ObservabilitySpanStatus status) {}

  @override
  Future<void> finish() async {}
}
