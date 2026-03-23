import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/presentation/home/home_screen.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: AppRoutes.home.path,
      builder: (context, state) => const SongListScreen(),
    ),
    GoRoute(
      path: AppRoutes.songReader.path,
      builder: (context, state) {
        final songId = state.pathParameters['songId'];

        if (songId == null) {
          return const HomeScreen();
        }

        return SongReaderScreen(songId: songId);
      },
    ),
  ],
);
