import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_selection.dart';

void main() {
  test('keeps the caret offset when the rewrite does not touch the prefix', () {
    const previous = '{title: A}\n[C]hello';
    const next = '{title: A}\n[D]hello';

    final selection = preserveSelectionAfterSourceRewrite(
      previousSource: previous,
      nextSource: next,
      previousSelection: const TextSelection.collapsed(offset: 3),
    );

    expect(selection.baseOffset, 3);
    expect(selection.isCollapsed, isTrue);
  });

  test('clamps the caret into range when the rewrite shortens the source', () {
    final selection = preserveSelectionAfterSourceRewrite(
      previousSource: 'abcdefgh',
      nextSource: 'abc',
      previousSelection: const TextSelection.collapsed(offset: 8),
    );

    expect(selection.baseOffset, lessThanOrEqualTo(3));
  });

  test('shared prefix and suffix lengths do not overlap', () {
    const left = 'xay';
    const right = 'xby';

    expect(sharedPrefixLength('aaa', 'aab'), 2);

    final prefixLength = sharedPrefixLength(left, right);
    expect(sharedSuffixLength(left, right, prefixLength), 1);
  });
}
