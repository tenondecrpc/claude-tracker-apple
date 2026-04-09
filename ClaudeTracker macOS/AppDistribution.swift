import Foundation

enum AppDistribution {
    case appStore
    case directDownload

    static var current: AppDistribution {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return .directDownload
        }

        let receiptPath = receiptURL.path
        let hasAppStoreReceiptPath = receiptPath.contains("/_MASReceipt/")
        let hasReceiptFile = FileManager.default.fileExists(atPath: receiptPath)

        return hasAppStoreReceiptPath && hasReceiptFile ? .appStore : .directDownload
    }

    var supportsInAppUpdates: Bool {
        self == .directDownload
    }
}
