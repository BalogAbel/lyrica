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
    final unrecognised = <String>[];
    var declarationsSeen = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final parsed = parseString(
        content: entity.readAsStringSync(),
        path: entity.path,
        throwIfDiagnostics: false,
      );

      final visitor = _AsyncProviderVisitor();
      parsed.unit.accept(visitor);
      declarationsSeen += visitor.declarationCount;

      String at(int offset) =>
          '${entity.path}:${parsed.lineInfo.getLocation(offset).lineNumber}';

      offenders.addAll(visitor.offsetsMissingPolicy.map(at));

      if (visitor.candidateCount != visitor.declarationCount) {
        unrecognised.add(
          '${entity.path}: ${visitor.candidateCount} variable declarations '
          'name a provider type, ${visitor.declarationCount} provider-creating '
          'calls were recognised',
        );
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

    // A guard that stops recognising a declaration shape reports no offenders
    // for a reason that has nothing to do with compliance. The cross-check
    // therefore has to be blind to shape, or it goes blind in exactly the same
    // place: it counts top-level declarations whose initializer names a
    // provider type at all, and requires the visitor to have recognised the
    // same number. That holds whether or not the escaping declaration carries
    // the policy — counting policy arguments instead would only catch the ones
    // that do.
    expect(
      unrecognised,
      isEmpty,
      reason:
          'the two counts disagree. Usually that means a provider declaration '
          'shape is escaping the visitor, so the check above proves less than '
          'it appears to; it can also mean an initializer merely names a '
          'provider type without creating one, which is a false alarm in the '
          'safe direction.\n${unrecognised.join('\n')}',
    );
    expect(
      declarationsSeen,
      greaterThan(0),
      reason: 'a scan that recognises nothing trivially reports no offenders',
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

    final visitor = _parse(source);

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

  test('the scan recognises every declaration shape', () {
    const source = '''
final plain = FutureProvider<int>((ref) async => 0);
final untyped = FutureProvider((ref) async => 0);
final tearOff = FutureProvider<int>(_build);
final disposed = FutureProvider.autoDispose<int>((ref) async => 0);
final familied = FutureProvider.autoDispose.family<int, String>(
  (ref, id) async => 0,
);
final streamed = StreamProvider<int>((ref) => const Stream.empty());
''';

    final visitor = _parse(source);

    expect(
      visitor.declarationCount,
      6,
      reason:
          'a declaration shape the visitor cannot see is a declaration free to '
          'skip the policy — the plain FutureProvider<T>(...) form has no '
          'target and must not be mistaken for a method call on a provider',
    );
    expect(visitor.offsetsMissingPolicy, hasLength(6));
  });

  test('the cross-check fires on a shape the visitor cannot recognise', () {
    const source = 'final aliased = FutureProvider<int>;';

    final visitor = _parse(source);

    expect(
      visitor.candidateCount,
      1,
      reason: 'the initializer names a provider type',
    );
    expect(
      visitor.declarationCount,
      0,
      reason:
          'and the visitor does not recognise it — which is the condition the '
          'cross-check exists to surface, whether or not a policy argument is '
          'present',
    );
  });

  test('a declaration that is not top-level counts on both sides', () {
    const source = '''
class Providers {
  static final store = FutureProvider<int>(
    (ref) async => 0,
    retry: noAutomaticProviderRetry,
  );
}
''';

    final visitor = _parse(source);

    expect(
      visitor.candidateCount,
      visitor.declarationCount,
      reason:
          'the candidate side must be as broad as the visitor, or a provider '
          'declared on a class reads as an escaping shape',
    );
    expect(visitor.declarationCount, 1);
    expect(visitor.offsetsMissingPolicy, isEmpty);
  });

  test('a method called on a provider is not a declaration', () {
    const source = '''
final derived = FutureProvider.autoDispose<int>(
  (ref) async => ref.watch(other.select((value) => value.id)),
  retry: noAutomaticProviderRetry,
);

final override = other.overrideWith((ref) async => 0);
''';

    final visitor = _parse(source);

    expect(
      visitor.declarationCount,
      1,
      reason: '.select and .overrideWith create no provider',
    );
    expect(visitor.offsetsMissingPolicy, isEmpty);
  });
}

_AsyncProviderVisitor _parse(String source) {
  final visitor = _AsyncProviderVisitor();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(visitor);
  return visitor;
}

/// Finds every call that creates a `FutureProvider` or `StreamProvider` and
/// records the ones whose arguments omit `retry: noAutomaticProviderRetry`.
///
/// Creation takes three shapes, and all three must be recognised by the shape
/// of the call rather than by what is passed to it. Keying off "an argument is
/// a function literal" would miss a create callback passed as a tear-off or a
/// variable, which is exactly the declaration that would then be free to skip
/// the policy:
///
/// - `FutureProvider<T>(create, …)` — no target; the type is the invocation's
///   own `methodName`
/// - `FutureProvider.autoDispose<T>(create, …)` and
///   `FutureProvider.autoDispose.family<T, A>(create, …)` — the builder members
///   parse as targeted invocations on the chain, not as separate node kinds
/// - a resolved constructor invocation
///
/// A method called *on* a provider (`.select`, `.overrideWith`) can sit on the
/// same chain but creates nothing, so a targeted invocation counts only when
/// the name it invokes is one of the builder members.
class _AsyncProviderVisitor extends RecursiveAstVisitor<void> {
  static const _providerTypes = {'FutureProvider', 'StreamProvider'};
  static const _builderMembers = {'autoDispose', 'family'};

  final List<int> offsetsMissingPolicy = [];
  int declarationCount = 0;

  /// Variable declarations whose initializer names a provider type at all,
  /// counted without looking at the shape of the call. This is the shape-blind
  /// half of the cross-check in the test above; on its own it proves nothing.
  ///
  /// Deliberately `visitVariableDeclaration` rather than the top-level form:
  /// the visitor recognises a declaration wherever it appears, so a candidate
  /// side that only looked at top-level variables would disagree with it for a
  /// provider declared on a class or inside a function — reporting an escaping
  /// shape when the real difference is where the declaration sits.
  int candidateCount = 0;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer != null &&
        _providerTypes.any(initializer.toSource().contains)) {
      candidateCount++;
    }

    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_chainRootIsAsyncProvider(node.function)) {
      _record(node.function, node.argumentList);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;

    if (target == null) {
      if (_providerTypes.contains(node.methodName.name)) {
        _record(node.methodName, node.argumentList);
      }
    } else if (_builderMembers.contains(node.methodName.name) &&
        _chainRootIsAsyncProvider(target)) {
      _record(node.methodName, node.argumentList);
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    if (_providerTypes.contains(type.name.lexeme)) {
      _record(type, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  void _record(AstNode callee, ArgumentList arguments) {
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
  bool _chainRootIsAsyncProvider(AstNode node) {
    var current = node;

    while (true) {
      switch (current) {
        case SimpleIdentifier(:final name):
          return _providerTypes.contains(name);
        case PrefixedIdentifier(:final prefix):
          current = prefix;
        case PropertyAccess(:final target?):
          current = target;
        case MethodInvocation(:final target?):
          current = target;
        case MethodInvocation(:final methodName):
          return _providerTypes.contains(methodName.name);
        case _:
          return false;
      }
    }
  }
}
