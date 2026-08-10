import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class DirectiveLineView extends StatelessWidget {
  const DirectiveLineView({super.key, required this.projection});

  final SongReaderDirectiveProjection projection;

  @override
  Widget build(BuildContext context) {
    final label = projection.value != null
        ? '{${projection.name}: ${projection.value}}'
        : '{${projection.name}}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label, style: ReaderTheme.of(context).directiveStyle),
    );
  }
}
