/// Reads one page of rows strictly after [after] (or from the start when
/// [after] is null), at most [limit] rows, ordered ascending by key.
typedef KeysetPageFetcher<R, K> =
    Future<List<R>> Function({required K? after, required int limit});

/// Why a paged read broke its contract with the server.
enum PagedReadContractViolation {
  /// A key was not strictly greater than the one before it (the cursor
  /// included): a duplicate, an overlap with an earlier page, or a row out of
  /// order.
  keyNotIncreasing,

  /// A page held more rows than the requested limit.
  pageOverLimit,
}

/// A paged read received data that breaks keyset paging's guarantees.
///
/// The message names the stream, the page and the reason only; it never
/// contains keys or row data.
class PagedReadContractException implements Exception {
  const PagedReadContractException({
    required this.stream,
    required this.pageIndex,
    required this.reason,
  });

  final String stream;

  /// Zero-based index of the page that violated the contract.
  final int pageIndex;
  final PagedReadContractViolation reason;

  @override
  String toString() =>
      'PagedReadContractException(stream: $stream, page: $pageIndex, '
      'reason: ${reason.name})';
}

/// A paged read was stopped because [readAllKeysetPages]'s `shouldContinue`
/// returned false. Nothing was fetched after the stop.
class PagedReadAbortedException implements Exception {
  const PagedReadAbortedException({required this.stream});

  final String stream;

  @override
  String toString() => 'PagedReadAbortedException(stream: $stream)';
}

/// Reads every row of a keyset-ordered source, page by page.
///
/// The first fetch passes `after: null`; each later fetch passes the key of
/// the previous page's last row. The read ends only on an empty page: a short
/// page is not an end signal, because a server-side row cap below [pageSize]
/// makes every page short. All rows read are returned in read order.
///
/// Every key must be strictly greater, by [compareKeys], than the key before
/// it (the cursor included); a page longer than [pageSize] is also rejected.
/// Both throw [PagedReadContractException]. A fetch error propagates unchanged
/// and no partial result is returned.
///
/// [shouldContinue] is checked before every fetch and after every fetch; when
/// it returns false the read throws [PagedReadAbortedException] and fetches
/// nothing more. [stream] names the source in exceptions for diagnostics.
///
/// [pageSize] must be positive.
Future<List<R>> readAllKeysetPages<R, K>({
  required KeysetPageFetcher<R, K> fetchPage,
  required K Function(R row) keyOf,
  required int Function(K a, K b) compareKeys,
  required int pageSize,
  bool Function()? shouldContinue,
  String stream = 'unnamed',
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
  }

  void ensureContinue() {
    if (shouldContinue != null && !shouldContinue()) {
      throw PagedReadAbortedException(stream: stream);
    }
  }

  final rows = <R>[];
  K? cursor;
  var pageIndex = 0;
  while (true) {
    ensureContinue();
    final page = await fetchPage(after: cursor, limit: pageSize);
    ensureContinue();

    if (page.isEmpty) {
      return rows;
    }
    if (page.length > pageSize) {
      throw PagedReadContractException(
        stream: stream,
        pageIndex: pageIndex,
        reason: PagedReadContractViolation.pageOverLimit,
      );
    }
    K? previous = cursor;
    for (final row in page) {
      final key = keyOf(row);
      if (previous != null && compareKeys(key, previous) <= 0) {
        throw PagedReadContractException(
          stream: stream,
          pageIndex: pageIndex,
          reason: PagedReadContractViolation.keyNotIncreasing,
        );
      }
      previous = key;
    }
    rows.addAll(page);
    cursor = previous;
    pageIndex++;
  }
}

/// Compares two canonical lowercase uuid strings in Postgres `uuid` order.
///
/// Valid only for columns of Postgres type `uuid`. Postgres orders a `uuid`
/// by its 16 bytes, which is exactly the order of its canonical lowercase hex
/// text, so a plain string comparison matches the server's `ORDER BY` and
/// `gt` filter. A `text` column is ordered by its collation, which can differ
/// from code-unit order, so this comparator must not be used for one.
int compareUuidKeys(String a, String b) => a.compareTo(b);
