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
/// point 2 for why, including the accepted consequence for error linking:
/// an error that crossed a span is trace-linked (`runInSpan` sets
/// `span.throwable`, and `SentrySpan.finish` records the association via
/// `Hub.setSpanContext` synchronously, before `_finishQuietly` yields, so it
/// is in place before the error can be captured by a zone/global handler). An
/// error thrown outside any span, or whose span never finished, is not
/// linked, because the ambient Scope span is not used.
class SentryObservability implements Observability {
  const SentryObservability();

  /// The ambient span handle, or null when there is none *or* the ambient
  /// span already finished. Zone values outlive the span they name: a
  /// `Timer`/microtask scheduled inside a span (e.g. Riverpod dependents
  /// notified during a refresh) runs later in that span's zone. A finished
  /// span must not be advertised as current: `SentryTracer.startChild` on a
  /// finished tracer returns a `NoOpSentrySpan` (all-zero ids), and its real
  /// ids would mis-correlate unrelated later requests with a finished trace.
  _SentrySpanHandle? get _current {
    final handle = Zone.current[_spanZoneKey] as _SentrySpanHandle?;
    return (handle == null || handle.isEnded) ? null : handle;
  }

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    final parent = _current;
    // A finished ambient span is already filtered out by `_current`, so
    // work scheduled from a dead span starts a NEW root instead of a child
    // of a finished tracer (which the SDK silently turns into a NoOp).
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
        // Status/throwable are already set above. Mark ended synchronously
        // (the SDK's own `finished` flag can lag behind an async finish),
        // then finish WITHOUT awaiting: on a root span `finish()` awaits
        // the transaction's transport send (an HTTP POST on web), and a
        // slow or hung collector must never stall the caller.
        handle.markEnded();
        unawaited(_finishQuietly(sentrySpan));
      }
    }, zoneValues: {_spanZoneKey: handle});
  }

  /// Finishes [span], swallowing any error: telemetry must never surface as an
  /// unhandled zone error or change the outcome of the instrumented
  /// operation. Defensive: transport errors are already swallowed by
  /// `Hub.captureTransaction` (hub.dart:596-602), so this only matters if the
  /// SDK's finish itself throws (e.g. a throwing `options.clock`).
  static Future<void> _finishQuietly(ISentrySpan span) async {
    try {
      await span.finish();
    } catch (_) {
      // Intentionally ignored -- see doc comment.
    }
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
    // A NoOp span (Sentry not initialised / span dropped by the SDK)
    // reports all-zero ids, which W3C declares invalid. Never emit that.
    if (trace.traceId == const SentryId.empty() ||
        trace.spanId == const SpanId.empty()) {
      return null;
    }
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

  bool _ended = false;

  /// True once [SentryObservability.runInSpan] is done with this span (set
  /// synchronously, before the async finish) or the SDK reports it finished.
  bool get isEnded => _ended || sentrySpan.finished;

  void markEnded() => _ended = true;

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
    // Iterate the scrubbed entries, not `scrubbed[key]`: scrubbing may rewrite
    // the key itself (a URL/JWT key, an oversized key), and a lookup by the
    // original key would silently drop the value. A dropped (sensitive) key
    // yields no entry at all.
    final scrubbed = scrubPii({key: value});
    if (scrubbed != null) {
      for (final entry in scrubbed.entries) {
        sentrySpan.setData(entry.key, entry.value);
      }
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
