#if os(macOS) && !CHIAKI_APP_STORE
    import ChiakiModels
    import Foundation
    import Network
    import OSLog

    /// Holds the Wi-Fi helper's input pipe for the lifetime of a stream on Wi-Fi.
    @MainActor final class SteadyWiFiSession {
        private static let log = Logger(subsystem: "io.github.chiaki-ng", category: "SteadyWiFi")
        private let monitor = NWPathMonitor()
        private var onWiFi = false
        private var worker: Process?
        private var lease: FileHandle?

        init() {
            monitor.pathUpdateHandler = { [weak self] path in
                let onWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
                Task { @MainActor in self?.updatePath(onWiFi: onWiFi) }
            }
            monitor.start(queue: DispatchQueue(label: "io.github.chiaki-ng.steady-wifi.path"))
        }

        func stop() {
            monitor.cancel()
            onWiFi = false
            release()
        }

        private func updatePath(onWiFi: Bool) {
            guard self.onWiFi != onWiFi else {
                return
            }
            self.onWiFi = onWiFi
            if onWiFi {
                acquire()
            } else {
                release()
            }
        }

        private func acquire() {
            guard worker == nil else {
                return
            }

            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", SteadyWiFiPreference.helperPath]
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor in self?.workerExited(status: status) }
            }
            do {
                try process.run()
                worker = process
                lease = pipe.fileHandleForWriting
            } catch {
                Self.log.error("Steady Wi-Fi could not start: \(error.localizedDescription, privacy: .public)")
            }
        }

        private func release() {
            try? lease?.close()
            lease = nil
        }

        private func workerExited(status: Int32) {
            let pathReturnedDuringRelease = onWiFi && lease == nil
            worker = nil
            release()
            if status != 0 {
                Self.log.error("Steady Wi-Fi helper exited with status \(status)")
            }
            if pathReturnedDuringRelease {
                acquire()
            }
        }
    }
#endif
