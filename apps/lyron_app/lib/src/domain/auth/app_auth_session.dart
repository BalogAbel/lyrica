class AppAuthSession {
  const AppAuthSession({
    required this.userId,
    required this.email,
    this.linkedProviders = const <String>[],
  });

  final String userId;
  final String email;
  final List<String> linkedProviders;
}
