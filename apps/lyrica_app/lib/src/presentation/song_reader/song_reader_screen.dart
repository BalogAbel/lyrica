import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyrica_app/src/presentation/song_reader/widgets/song_reader_header.dart';
import 'package:lyrica_app/src/presentation/song_reader/widgets/song_section_view.dart';

class SongReaderScreen extends ConsumerStatefulWidget {
  const SongReaderScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<SongReaderScreen> createState() => _SongReaderScreenState();
}

class _SongReaderScreenState extends ConsumerState<SongReaderScreen> {
  static const _contentWidth = 960.0;
  static const _contentPadding = EdgeInsets.all(24);

  late final SongReaderController _controller = SongReaderController();

  void _updateState(void Function(SongReaderController controller) update) {
    setState(() {
      update(_controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    final readerAsync = ref.watch(songLibraryReaderProvider(widget.songId));

    return Scaffold(
      appBar: AppBar(title: const Text('Song reader')),
      body: SafeArea(
        child: readerAsync.when(
          loading: () => const Center(child: Text('Loading song...')),
          error: (error, stackTrace) {
            return const Center(child: Text('Unable to load song.'));
          },
          data: (SongReaderResult result) {
            final projection = SongReaderProjection(
              song: result.song,
              state: _controller.state,
            );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentWidth),
                child: ListView(
                  padding: _contentPadding,
                  children: [
                    SongReaderHeader(
                      projection: projection,
                      hasRecoverableWarnings: result.hasRecoverableWarnings,
                      warningCount: result.song.diagnostics.length,
                      onToggleViewMode: () {
                        _updateState(
                          (controller) => controller.toggleViewMode(),
                        );
                      },
                      onTransposeDown: () {
                        _updateState(
                          (controller) => controller.transposeDown(),
                        );
                      },
                      onTransposeUp: () {
                        _updateState((controller) => controller.transposeUp());
                      },
                      onDecreaseFontScale: () {
                        _updateState((controller) {
                          controller.setSharedFontScale(
                            controller.state.sharedFontScale - 0.1,
                          );
                        });
                      },
                      onIncreaseFontScale: () {
                        _updateState((controller) {
                          controller.setSharedFontScale(
                            controller.state.sharedFontScale + 0.1,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    for (final section in projection.sections) ...[
                      SongSectionView(
                        section: section,
                        viewMode: projection.viewMode,
                        sharedFontScale: projection.sharedFontScale,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
