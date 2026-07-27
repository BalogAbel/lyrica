import 'package:flutter/services.dart';

TextSelection preserveSelectionAfterSourceRewrite({
  required String previousSource,
  required String nextSource,
  required TextSelection previousSelection,
}) {
  if (!previousSelection.isValid) {
    return TextSelection.collapsed(offset: nextSource.length);
  }

  final prefixLength = sharedPrefixLength(previousSource, nextSource);
  final suffixLength = sharedSuffixLength(
    previousSource,
    nextSource,
    prefixLength,
  );
  final previousChangedEnd = previousSource.length - suffixLength;
  final nextChangedEnd = nextSource.length - suffixLength;
  final delta = nextSource.length - previousSource.length;

  int mapOffset(int offset) {
    if (offset <= prefixLength) {
      return offset;
    }
    if (offset >= previousChangedEnd) {
      return (offset + delta).clamp(0, nextSource.length);
    }
    return nextChangedEnd.clamp(0, nextSource.length);
  }

  return TextSelection(
    baseOffset: mapOffset(previousSelection.baseOffset),
    extentOffset: mapOffset(previousSelection.extentOffset),
    affinity: previousSelection.affinity,
    isDirectional: previousSelection.isDirectional,
  );
}

int sharedPrefixLength(String left, String right) {
  final maxLength = left.length < right.length ? left.length : right.length;
  var index = 0;
  while (index < maxLength &&
      left.codeUnitAt(index) == right.codeUnitAt(index)) {
    index += 1;
  }
  return index;
}

int sharedSuffixLength(String left, String right, int prefixLength) {
  final maxLength = left.length < right.length ? left.length : right.length;
  var count = 0;
  while (count < maxLength - prefixLength &&
      left.codeUnitAt(left.length - count - 1) ==
          right.codeUnitAt(right.length - count - 1)) {
    count += 1;
  }
  return count;
}
