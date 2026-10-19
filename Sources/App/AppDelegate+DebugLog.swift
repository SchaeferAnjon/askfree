import Foundation
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate {
    func debugLog(_ message: String) {
        let logFile = AppIdentity.debugLogFileURL
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let maxBytes = debugLogMaxBytes
        debugLogQueue.async {
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)

            let attributes = try? fileManager.attributesOfItem(atPath: logFile.path)
            let currentBytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            if currentBytes + UInt64(data.count) > maxBytes {
                try? fileManager.removeItem(at: logFile)
            }

            if fileManager.fileExists(atPath: logFile.path),
               let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFile.path)
        }
    }
}
