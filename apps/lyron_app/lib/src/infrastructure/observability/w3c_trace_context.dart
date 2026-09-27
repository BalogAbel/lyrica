/// Builds a W3C Trace Context `traceparent` header value from a Sentry
/// trace id (32 lowercase hex chars) and span id (16 lowercase hex chars).
/// Sentry's own id formats are already W3C-shaped — this is pure string
/// assembly, with no Sentry dependency, so it is testable in isolation and
/// portable to any future tracing backend that also produces hex ids in
/// these lengths.
String buildTraceParent({
  required String traceId,
  required String spanId,
  bool sampled = true,
}) {
  final flags = sampled ? '01' : '00';
  return '00-$traceId-$spanId-$flags';
}
