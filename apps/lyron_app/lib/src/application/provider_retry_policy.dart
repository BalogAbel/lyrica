/// The retry policy for every provider in this application: never retry.
///
/// Riverpod 3 retries a failed provider up to ten times with exponential
/// backoff by default. While retrying, the element stays in
/// `AsyncLoading(retrying: true)` instead of settling into `AsyncError`, so the
/// failure never reaches the UI and `await provider.future` never completes
/// with it — it fails later, and differently, once autoDispose collects the
/// still-loading element.
///
/// That contradicts the failure contract this application already has: a
/// failure surfaces immediately, and retrying is an explicit user action. See
/// ADR-032.
///
/// This is declared on the providers rather than on the container because
/// Riverpod resolves retry as `origin.retry ?? container.retry ?? defaultRetry`
/// and `origin` survives test overrides, so one declaration gives production
/// and every test the same semantics without wiring it into each
/// `ProviderScope`. `test/application/provider_retry_policy_test.dart` fails
/// when an async provider omits it.
Duration? noAutomaticProviderRetry(int retryCount, Object error) => null;
