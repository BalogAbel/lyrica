import 'dart:async';

import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';
import 'package:lyron_app/src/infrastructure/observability/w3c_trace_context.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _spanZoneKey = #lyronCurrentObservabilitySpan;

/// Sentry-backed [Observability] adapter. Span parent/child resolution
/// runs through a dedicated Dart Zone value ([_spanZoneKey]), not
/// Sentry's own ambient `Scope` -- see
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md
/// point 2 for why, including the accepted consequence that
/// SDK-auto-captured unhandled errors are never trace-linked as a result.
class SentryObservability implements Observability {
  const SentryObservability();

  _SentrySpanHandle? get _current =>
      Zone.current[_spanZoneKey] as _SentrySpanHandle?;

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    final parent = _current;
    final sentrySpan = parent == null
        ? Sentry.startTransaction(name, operation, bindToScope: false)
        : parent.sentrySpan.startChild(operation, description: name);

    final scrubbed = scrubPii(data);
    if (scrubbed != null) {
      for (final entry in scrubbed.entries) {
        sentrySpan.setData(entry.key, entry.value);
      }
    }

    final handle = _SentrySpanHandle(sentrySpan);

    return runZoned<Future<T>>(() async {
      try {
        final result = await body(handle);
        // Explicit, not relying on finish()'s default: a root Transaction
        // defaults an unset status to `ok` on finish, but a plain child
        // span (from `startChild`) does not reliably do the same --
        // setting it explicitly here covers both cases identically.
        sentrySpan.status = const SpanStatus.ok();
        return result;
      } catch (error) {
        // `internalError` here is a span-status marker ("this span did
        // not complete normally"), not a Sentry issue -- captureException
        // is never called here, so classified/expected failures (e.g. a
        // ConnectivityFailure during an offline refresh) never file an
        // issue just because they passed through a span. See ADR-036
        // point 4.
        sentrySpan.throwable = error;
        sentrySpan.status = const SpanStatus.internalError();
        rethrow;
      } finally {
        await sentrySpan.finish();
      }
    }, zoneValues: {_spanZoneKey: handle});
  }

  @override
  ObservabilitySpan get currentSpan =>
      _current ?? const NoopObservabilitySpan();

  @override
  String? get currentTraceParent {
    final span = _current?.sentrySpan;
    if (span == null) return null;
    // `toSentryTrace()` is the public API for reading a span's trace/span
    // id and sampling decision. `ISentrySpan.samplingDecision` also exists
    // but is annotated `@internal` in the SDK source -- using it directly
    // would trip `invalid_use_of_internal_member` under `flutter analyze`.
    final trace = span.toSentryTrace();
    return buildTraceParent(
      traceId: trace.traceId.toString(),
      spanId: trace.spanId.toString(),
      sampled: trace.sampled ?? true,
    );
  }

  @override
  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  }) {
    final activeSpan = _current?.sentrySpan;
    final scrubbedExtra = scrubPii(extra);
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (activeSpan != null) {
          scope.span = activeSpan;
        }
        if (scrubbedExtra != null) {
          for (final entry in scrubbedExtra.entries) {
            scope.setContexts(entry.key, entry.value);
          }
        }
      },
    );
  }

  @override
  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        level: _toSentryLevel(level),
        data: scrubPii(data),
      ),
    );
  }

  @override
  void setUserContext({required String userId, String? organizationId}) {
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: userId));
      if (organizationId != null) {
        scope.setContexts('organization', {'id': organizationId});
      }
    });
  }

  @override
  void clearUserContext() {
    Sentry.configureScope((scope) {
      scope.setUser(null);
      // Must also clear the 'organization' context setUserContext sets --
      // clearing only the user would leave a stale organization id
      // attached to events fired after sign-out.
      scope.removeContexts('organization');
    });
  }

  SentryLevel _toSentryLevel(BreadcrumbLevel level) {
    switch (level) {
      case BreadcrumbLevel.debug:
        return SentryLevel.debug;
      case BreadcrumbLevel.info:
        return SentryLevel.info;
      case BreadcrumbLevel.warning:
        return SentryLevel.warning;
      case BreadcrumbLevel.error:
        return SentryLevel.error;
    }
  }
}

class _SentrySpanHandle implements ObservabilitySpan {
  _SentrySpanHandle(this.sentrySpan);

  final ISentrySpan sentrySpan;

  @override
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  }) {
    final child = sentrySpan.startChild(operation, description: description);
    final scrubbed = scrubPii(data);
    if (scrubbed != null) {
      for (final entry in scrubbed.entries) {
        child.setData(entry.key, entry.value);
      }
    }
    return _SentrySpanHandle(child);
  }

  @override
  void setData(String key, Object? value) {
    final scrubbed = scrubPii({key: value});
    if (scrubbed != null && scrubbed.containsKey(key)) {
      sentrySpan.setData(key, scrubbed[key]);
    }
  }

  @override
  void setStatus(ObservabilitySpanStatus status) {
    sentrySpan.status = _toSentryStatus(status);
  }

  @override
  Future<void> finish() => sentrySpan.finish();

  SpanStatus _toSentryStatus(ObservabilitySpanStatus status) {
    switch (status) {
      case ObservabilitySpanStatus.ok:
        return const SpanStatus.ok();
      case ObservabilitySpanStatus.cancelled:
        return const SpanStatus.cancelled();
      case ObservabilitySpanStatus.internalError:
        return const SpanStatus.internalError();
      case ObservabilitySpanStatus.unknown:
        return const SpanStatus.unknown();
    }
  }
}
