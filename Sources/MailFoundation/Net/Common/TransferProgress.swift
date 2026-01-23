//
// TransferProgress.swift
//
// Progress reporting for message transfers.
//

public protocol TransferProgress: AnyObject {
    func report(bytesTransferred: Int64, totalSize: Int64)
    func report(bytesTransferred: Int64)
}

public extension TransferProgress {
    func report(bytesTransferred: Int64) {
        report(bytesTransferred: bytesTransferred, totalSize: 0)
    }
}

public typealias ITransferProgress = TransferProgress
