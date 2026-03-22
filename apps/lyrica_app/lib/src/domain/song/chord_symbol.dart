class ChordSymbol {
  ChordSymbol._({
    required this.rootPitchClass,
    required this.qualitySuffix,
    required this.isParenthesized,
    this.bassPitchClass,
  });

  static const List<String> _noteNames = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static const Map<String, int> _pitchClasses = <String, int>{
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };

  final int rootPitchClass;
  final String qualitySuffix;
  final int? bassPitchClass;
  final bool isParenthesized;

  factory ChordSymbol.parse(String input) {
    var text = input.trim();
    var isParenthesized = false;

    if (text.isEmpty) {
      throw FormatException('Chord symbol cannot be empty.');
    }

    if (text.startsWith('(') && text.endsWith(')') && text.length > 2) {
      isParenthesized = true;
      text = text.substring(1, text.length - 1);
    }

    if (text.contains('(') || text.contains(')')) {
      throw FormatException('Chord symbol has unbalanced parentheses: $input');
    }

    final bassSeparatorIndex = text.indexOf('/');
    final lastBassSeparatorIndex = text.lastIndexOf('/');
    if (bassSeparatorIndex != lastBassSeparatorIndex) {
      throw FormatException('Chord symbol has an invalid slash chord: $input');
    }

    final rootText = bassSeparatorIndex == -1
        ? text
        : text.substring(0, bassSeparatorIndex);
    final bassText = bassSeparatorIndex == -1
        ? null
        : text.substring(bassSeparatorIndex + 1);

    if (rootText.isEmpty) {
      throw FormatException('Chord symbol is missing a root note: $input');
    }

    if (bassText != null && bassText.isEmpty) {
      throw FormatException('Chord symbol is missing a bass note: $input');
    }

    final rootSplit = _splitPitchClass(rootText);
    final bass = bassText == null ? null : _parsePitchClass(bassText);

    return ChordSymbol._(
      rootPitchClass: rootSplit.pitchClass,
      qualitySuffix: rootSplit.suffix,
      isParenthesized: isParenthesized,
      bassPitchClass: bass,
    );
  }

  String get rootNoteName => _noteNames[rootPitchClass];

  String? get bassNoteName => bassPitchClass == null
      ? null
      : _noteNames[bassPitchClass!];

  String get displayName {
    final buffer = StringBuffer();
    if (isParenthesized) {
      buffer.write('(');
    }

    buffer.write(rootNoteName);
    buffer.write(qualitySuffix);

    if (bassPitchClass != null) {
      buffer
        ..write('/')
        ..write(bassNoteName);
    }

    if (isParenthesized) {
      buffer.write(')');
    }

    return buffer.toString();
  }

  ChordSymbol transpose(int semitoneOffset) {
    return ChordSymbol._(
      rootPitchClass: _wrapPitchClass(rootPitchClass + semitoneOffset),
      qualitySuffix: qualitySuffix,
      isParenthesized: isParenthesized,
      bassPitchClass: bassPitchClass == null
          ? null
          : _wrapPitchClass(bassPitchClass! + semitoneOffset),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChordSymbol &&
        other.rootPitchClass == rootPitchClass &&
        other.qualitySuffix == qualitySuffix &&
        other.bassPitchClass == bassPitchClass &&
        other.isParenthesized == isParenthesized;
  }

  @override
  int get hashCode => Object.hash(
    rootPitchClass,
    qualitySuffix,
    bassPitchClass,
    isParenthesized,
  );

  static int _parsePitchClass(String text) {
    final pitchClass = _pitchClasses[text];
    if (pitchClass == null) {
      throw FormatException('Unsupported chord pitch class: $text');
    }

    return pitchClass;
  }

  static _PitchClassSplit _splitPitchClass(String text) {
    if (text.length >= 2) {
      final twoCharacterPitchClass = text.substring(0, 2);
      if (_pitchClasses.containsKey(twoCharacterPitchClass)) {
        return _PitchClassSplit(
          pitchClass: _pitchClasses[twoCharacterPitchClass]!,
          suffix: text.substring(2),
        );
      }
    }

    final oneCharacterPitchClass = text.substring(0, 1);
    final pitchClass = _pitchClasses[oneCharacterPitchClass];
    if (pitchClass == null) {
      throw FormatException('Unsupported chord pitch class: $text');
    }

    return _PitchClassSplit(
      pitchClass: pitchClass,
      suffix: text.substring(1),
    );
  }

  static int _wrapPitchClass(int pitchClass) {
    var wrapped = pitchClass % 12;
    if (wrapped < 0) {
      wrapped += 12;
    }

    return wrapped;
  }
}

class _PitchClassSplit {
  const _PitchClassSplit({
    required this.pitchClass,
    required this.suffix,
  });

  final int pitchClass;
  final String suffix;
}
