import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Riverpod 3 retries a failed provider up to ten times by default, which keeps
/// the failure from ever settling into `AsyncError` and so from ever reaching
/// the UI. Every async provider therefore opts out explicitly. See ADR-032.
///
/// The scan parses each library rather than pattern-matching its text. A
/// regex over source cannot tell a provider declaration from the same words
/// inside a comment or a string, and cannot reliably find where a declaration
/// ends — string interpolation alone (`'${f('(')}'`) is enough to desynchronise
/// bracket counting and let one declaration absorb the next one's arguments.
void main() {
  test('every async provider declares the no-retry policy', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final parsed = parseString(
        content: entity.readAsStringSync(),
        path: entity.path,
        throwIfDiagnostics: false,
      );

      final visitor = _AsyncProviderVisitor();
      parsed.unit.accept(visitor);

      for (final offset in visitor.offsetsMissingPolicy) {
        final location = parsed.lineInfo.getLocation(offset);
        offenders.add('${entity.path}:${location.lineNumber}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These async providers do not declare '
          'retry: noAutomaticProviderRetry, so Riverpod 3 will retry them on '
          'failure and their error will never reach the UI. See ADR-032.\n'
          '${offenders.join('\n')}',
    );
  });

  test('the scan sees through text a regex would trip over', () {
    const source = '''
// FutureProvider<int>((ref) => 0);
const banner = 'FutureProvider<int>((ref) => 0)';

final interpolated = FutureProvider.autoDispose<int>((ref) {
  return int.parse('\${_label('(')} 1');
}, retry: noAutomaticProviderRetry);

final arrowed = FutureProvider.autoDispose<int>((ref) => 0);
''';

    final visitor = _AsyncProviderVisitor();
    parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.accept(visitor);

    expect(
      visitor.declarationCount,
      2,
      reason:
          'the commented-out and quoted occurrences must not count as '
          'declarations',
    );
    expect(
      visitor.offsetsMissingPolicy,
      hasLength(1),
      reason:
          'the interpolated declaration carries the policy and the arrow-bodied '
          'one does not; unbalanced brackets inside the interpolation must not '
          'let the first one cover the second',
    );
  });
}

/// Finds every call that creates a `FutureProvider` or `StreamProvider` —
/// including the `.autoDispose` and `.family` builder chains — and records the
/// ones whose arguments omit `retry: noAutomaticProviderRetry`.
class _AsyncProviderVisitor extends RecursiveAstVisitor<void> {
  final List<int> offsetsMissingPolicy = [];
  int declarationCount = 0;

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _record(node.function, node.argumentList);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.type, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  void _record(AstNode callee, ArgumentList arguments) {
    if (!_isAsyncProviderChain(callee)) return;

    // The call that actually creates the provider is the one handed the create
    // callback; `FutureProvider.autoDispose` on its own creates nothing.
    final createsProvider = arguments.arguments.any(
      (argument) =>
          argument is FunctionExpression ||
          (argument is NamedExpression &&
              argument.expression is FunctionExpression),
    );
    if (!createsProvider) return;

    declarationCount++;

    final hasPolicy = arguments.arguments.any(
      (argument) =>
          argument is NamedExpression &&
          argument.name.label.name == 'retry' &&
          argument.expression.toSource() == 'noAutomaticProviderRetry',
    );
    if (!hasPolicy) offsetsMissingPolicy.add(callee.offset);
  }

  /// Walks a receiver chain such as `FutureProvider.autoDispose.family` down to
  /// its leftmost identifier.
  bool _isAsyncProviderChain(AstNode node) {
    var current = node;

    while (true) {
      switch (current) {
        case SimpleIdentifier(:final name):
          return name == 'FutureProvider' || name == 'StreamProvider';
        case PrefixedIdentifier(:final prefix):
          current = prefix;
        case PropertyAccess(:final target?):
          current = target;
        case MethodInvocation(:final target?):
          current = target;
        case NamedType(:final name):
          return name.lexeme == 'FutureProvider' ||
              name.lexeme == 'StreamProvider';
        case _:
          return false;
      }
    }
  }
}
