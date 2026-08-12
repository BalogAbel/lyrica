import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';

void main() {
  testWidgets('measureSongReaderCharWidths returns the reader metrics', (
    tester,
  ) async {
    late SongReaderCharWidths measured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            measured = measureSongReaderCharWidths(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(measured.metrics, SongReaderMetrics.legacy);
  });
}
