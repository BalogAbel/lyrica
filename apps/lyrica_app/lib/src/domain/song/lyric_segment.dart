class LyricSegment {
  const LyricSegment({this.leadingChord, required this.text});

  final String? leadingChord;
  final String text;

  @override
  bool operator ==(Object other) {
    return other is LyricSegment &&
        other.leadingChord == leadingChord &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(leadingChord, text);
}
