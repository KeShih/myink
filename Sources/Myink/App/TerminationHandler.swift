import AppKit

/// Flushes state and exits on SIGTERM/SIGINT (e.g. `pkill` from scripts/install.sh).
final class TerminationHandler {
    private var sources: [any DispatchSourceSignal] = []

    init(onTerminate: @escaping () -> Void) {
        // The sources deliver on the main queue, so the handler runs on the main actor; the unchecked
        // capture only crosses the SDK's @Sendable handler boundary.
        nonisolated(unsafe) let onTerminate = onTerminate
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    Log.app.notice("Received signal \(signalNumber); flushing and exiting")
                    onTerminate()
                    exit(0)
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}
