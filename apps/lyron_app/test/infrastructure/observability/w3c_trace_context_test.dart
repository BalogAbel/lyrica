import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/w3c_trace_context.dart';

void main() {
  group('buildTraceParent', () {
    test('matches the full traceparent regex', () {
      final header = buildTraceParent(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
      );

      expect(
        header,
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$')),
      );
      expect(header, '00-0123456789abcdef0123456789abcdef-0123456789abcdef-01');
    });

    test('encodes an unsampled decision as flag 00', () {
      final header = buildTraceParent(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
        sampled: false,
      );

      expect(header, endsWith('-00'));
    });
  });
}
