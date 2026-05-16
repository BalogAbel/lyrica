/// File extensions accepted by the ChordPro importer (without leading dot).
/// Extend this set to support additional formats without changing any other file.
const Set<String> kSupportedChordProExtensions = {'cho', 'chordpro', 'chopro'};

/// Raw input from the file picker, before parsing.
class ImportFileInput {
  const ImportFileInput({required this.filename, required this.source});

  final String filename;
  final String source;
}

sealed class ImportFileResult {
  const ImportFileResult();
}

/// File was parsed and has no title conflict with an existing song.
/// [source] is the normalised ChordPro text ready for storage.
class ImportSuccess extends ImportFileResult {
  const ImportSuccess({
    required this.title,
    required this.source,
    required this.filename,
  });

  final String title;
  final String source;
  final String filename;
}

/// File title matches an existing song (case-insensitive).
class ImportDuplicate extends ImportFileResult {
  const ImportDuplicate({
    required this.filename,
    required this.incomingSource,
    required this.incomingTitle,
    required this.existingSongId,
    required this.existingTitle,
  });

  final String filename;
  final String incomingSource;
  final String incomingTitle;
  final String existingSongId;
  final String existingTitle;
}

/// File could not be read or parsed.
class ImportError extends ImportFileResult {
  const ImportError({required this.filename, required this.reason});

  final String filename;
  final String reason;
}

class ImportBatchResult {
  const ImportBatchResult({
    required this.successes,
    required this.duplicates,
    required this.errors,
  });

  final List<ImportSuccess> successes;
  final List<ImportDuplicate> duplicates;
  final List<ImportError> errors;

  bool get hasIssues => duplicates.isNotEmpty || errors.isNotEmpty;
}

enum DuplicateResolution { overwrite, skip }

class ResolvedDuplicate {
  const ResolvedDuplicate({required this.duplicate, required this.resolution});

  final ImportDuplicate duplicate;
  final DuplicateResolution resolution;
}
