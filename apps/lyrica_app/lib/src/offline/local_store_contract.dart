class LocalStoreContract {
  const LocalStoreContract({
    required this.engine,
    required this.usesSyncQueue,
    required this.readStrategy,
  });

  final String engine;
  final bool usesSyncQueue;
  final String readStrategy;
}

const defaultLocalStoreContract = LocalStoreContract(
  engine: 'Drift',
  usesSyncQueue: true,
  readStrategy: 'local-first',
);
