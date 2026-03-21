import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

void main() {
  test('home route path remains stable', () {
    expect(AppRoutes.home.path, '/');
  });
}
