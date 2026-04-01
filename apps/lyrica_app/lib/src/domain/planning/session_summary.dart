import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.name,
    required this.position,
    required this.items,
  });

  final String id;
  final String name;
  final int position;
  final List<SessionItemSummary> items;

  @override
  bool operator ==(Object other) {
    return other is SessionSummary &&
        other.id == id &&
        other.name == name &&
        other.position == position &&
        _listEquals(other.items, items);
  }

  @override
  int get hashCode => Object.hash(id, name, position, Object.hashAll(items));
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
