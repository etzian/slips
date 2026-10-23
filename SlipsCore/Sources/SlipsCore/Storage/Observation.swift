import GRDB

extension AppDatabase {
    /// Values of `fetch`, re-emitted after every committed change to what it read. Screens consume the
    /// stream through the typed observers below, so they never see GRDB.
    func observe<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncThrowingStream<T, any Error> {
        let observation = ValueObservation.tracking(fetch)
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated)),
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
