class ChordproNormalizer {
  static final _aliasPattern = RegExp(
    r'^\s*\{([A-Za-z][A-Za-z0-9_-]*)(:[^}]*)?\}\s*$',
  );

  static const _aliases = <String, String>{
    't': 'title',
    'st': 'subtitle',
    'c': 'comment',
    'soc': 'start_of_chorus',
    'eoc': 'end_of_chorus',
    'sov': 'start_of_verse',
    'eov': 'end_of_verse',
    'sob': 'start_of_bridge',
    'eob': 'end_of_bridge',
    'sot': 'start_of_tab',
    'eot': 'end_of_tab',
  };

  String normalize(String source) =>
      source.split(RegExp(r'\r?\n')).map(_normalizeLine).join('\n');

  String _normalizeLine(String line) {
    final match = _aliasPattern.firstMatch(line);
    if (match == null) return line;
    final name = match.group(1)!.toLowerCase();
    final rest = match.group(2) ?? '';
    final canonical = _aliases[name];
    if (canonical == null) return line;
    return '{$canonical$rest}';
  }
}
