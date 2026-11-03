extension Task where Success == Never, Failure == Never {
    static func waitUntilCancelled() async {
        let (cancellation, continuation) = AsyncStream<Void>.makeStream()
        for await _ in cancellation {}
        continuation.finish()
    }
}
