import SessionKit

extension SessionController {
    /// Root view cancellation still awaits real effects when a UI transition is in flight.
    func shutdown() async {
        do { try await close() } catch {
            // A forced view teardown cannot keep an editor open for a save retry.
            // Accepted inputs are already durable; do not leave a task or lock behind.
            isTransitioning = true
            await stopAgent()
            finishRun()
            isTransitioning = false
        }
    }

    func finishRun() {
        ownership?.release()
        ownership = nil
        isClosed = true
        let continuation = runEnd
        runEnd = nil
        isRunning = false
        continuation?.resume()
    }
}
