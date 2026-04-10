import Foundation

enum AppDistribution {
    case appStore
    case directDownload

    static var current: AppDistribution {
        let receiptURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("_MASReceipt", isDirectory: true)
            .appendingPathComponent("receipt", isDirectory: false)

        return FileManager.default.fileExists(atPath: receiptURL.path) ? .appStore : .directDownload
    }

    var supportsInAppUpdates: Bool {
        self == .directDownload
    }
}
