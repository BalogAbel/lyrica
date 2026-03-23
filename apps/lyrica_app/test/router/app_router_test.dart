import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

void main() {
  test('list and reader routes remain stable', () {
    expect(AppRoutes.home.path, '/');
    expect(AppRoutes.songReader.path, '/songs/:songId');
  });
}
