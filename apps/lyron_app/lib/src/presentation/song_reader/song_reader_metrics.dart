/// Layout constants shared by the reader renderer and the fit estimator.
///
/// These live in one place because the estimator has to reproduce the
/// renderer's spacing exactly; duplicated constants drift silently.
const double lineRunSpacing = 10.0;
const double chordOnlySpacing = 22.0;
const double chordToLyricGap = 2.0;
