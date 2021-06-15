//
//  CompactBlockProcessingOperation.swift
//  ZcashLightClientKit
//
//  Created by Francisco Gindre on 10/15/19.
//  Copyright © 2019 Electric Coin Company. All rights reserved.
//

import Foundation

class CompactBlockScanningOperation: ZcashOperation {
    
    override var isConcurrent: Bool { false }
    
    override var isAsynchronous: Bool { false }
    
    var rustBackend: ZcashRustBackendWelding.Type
    
    private var cacheDb: URL
    private var dataDb: URL
    private var limit: UInt32
    init(rustWelding: ZcashRustBackendWelding.Type, cacheDb: URL, dataDb: URL, limit: UInt32 = 0) {
        rustBackend = rustWelding
        self.cacheDb = cacheDb
        self.dataDb = dataDb
        self.limit = limit
        super.init()
    }
    
    override func main() {
        guard !shouldCancel() else {
            cancel()
            return
        }
        self.startedHandler?()
        guard self.rustBackend.scanBlocks(dbCache: self.cacheDb, dbData: self.dataDb, limit: limit) else {
            self.error = self.rustBackend.lastError() ?? ZcashOperationError.unknown
            LoggerProxy.debug("block scanning failed with error: \(String(describing: self.error))")
            self.fail()
            return
        }
    }
}

public class SDKMetrics {
    
    struct BlockMetricReport {
        var startHeight: BlockHeight
        var targetHeight: BlockHeight
        var duration: TimeInterval
        var task: TaskReported
    }
    
    enum TaskReported: String {
        case scanBlocks
    }
    static let startBlockHeightKey = "SDKMetrics.startBlockHeightKey"
    static let targetBlockHeightKey = "SDKMetrics.targetBlockHeightKey"
    static let progressHeightKey = "SDKMetrics.progressHeight"
    static let startDateKey = "SDKMetrics.startDateKey"
    static let endDateKey = "SDKMetrics.endDateKey"
    static let taskReportedKey = "SDKMetrics.taskReported"
    static let notificationName = Notification.Name("SDKMetrics.Notification")
    
    static func blockReportFromNotification(_ notification: Notification) -> BlockMetricReport? {
        
        guard notification.name == notificationName,
              let info = notification.userInfo,
              let startHeight = info[startBlockHeightKey] as? BlockHeight,
              let targetHeight = info[targetBlockHeightKey] as? BlockHeight,
              let task = info[taskReportedKey] as? TaskReported,
              let startDate = info[startDateKey] as? Date,
              let endDate = info[endDateKey] as? Date else {
            return nil
        }
        
        return BlockMetricReport(startHeight: startHeight, targetHeight: targetHeight, duration: abs(startDate.timeIntervalSinceReferenceDate - endDate.timeIntervalSinceReferenceDate), task: task)
    }
    
    static func progressReportNotification(progress: BlockProgressReporting, start: Date, end: Date, task: SDKMetrics.TaskReported) -> Notification {
        var notification = Notification(name: notificationName)
        notification.userInfo = [
            startBlockHeightKey : progress.startHeight,
            targetBlockHeightKey : progress.targetHeight,
            progressHeightKey : progress.progressHeight,
            startDateKey : start,
            endDateKey : end,
            taskReportedKey : task
        ]
        
        return notification
    }
}

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: SDKMetrics.BlockMetricReport) {
        let literal = "\(value.task) - \(abs(value.startHeight - value.targetHeight)) processed on \(value.duration) seconds"
        appendLiteral(literal)
    }
}

class CompactBlockBatchScanningOperation: ZcashOperation {
    
    override var isConcurrent: Bool { false }
    
    override var isAsynchronous: Bool { false }
    
    var rustBackend: ZcashRustBackendWelding.Type
    private weak var progressDelegate: CompactBlockProgressDelegate?
    private var cacheDb: URL
    private var dataDb: URL
    private var batchSize: UInt32
    private var blockRange: CompactBlockRange
    private var transactionRepository: TransactionRepository
    
    init(rustWelding: ZcashRustBackendWelding.Type,
         cacheDb: URL,
         dataDb: URL,
         transactionRepository: TransactionRepository,
         range: CompactBlockRange,
         batchSize: UInt32 = 100,
         progressDelegate: CompactBlockProgressDelegate? = nil) {
        rustBackend = rustWelding
        self.cacheDb = cacheDb
        self.dataDb = dataDb
        self.transactionRepository = transactionRepository
        self.blockRange = range
        self.batchSize = batchSize
        self.progressDelegate = progressDelegate
        super.init()
    }
    
    override func main() {
        guard !shouldCancel() else {
            cancel()
            return
        }
        self.startedHandler?()
        do {
            if batchSize == 0 {
                let scanStartTime = Date()
                guard self.rustBackend.scanBlocks(dbCache: self.cacheDb, dbData: self.dataDb, limit: batchSize) else {
                    self.scanFailed(self.rustBackend.lastError() ?? ZcashOperationError.unknown)
                    return
                }
                let scanFinishTime = Date()
                NotificationCenter.default.post(SDKMetrics.progressReportNotification(
                                                    progress: BlockProgress(startHeight: self.blockRange.lowerBound,
                                                                            targetHeight: self.blockRange.upperBound,
                                                                            progressHeight: self.blockRange.upperBound),
                                                    start: scanStartTime,
                                                    end: scanFinishTime,
                                                    task: .scanBlocks))
                LoggerProxy.debug("Scanned \(blockRange.count) blocks in \(scanFinishTime.timeIntervalSinceReferenceDate - scanStartTime.timeIntervalSinceReferenceDate) seconds")
            } else {
                let scanStartHeight = try transactionRepository.lastScannedHeight()
                let targetScanHeight = blockRange.upperBound
                var scannedNewBlocks = false
                var lastScannedHeight = scanStartHeight
                repeat {
                    guard !shouldCancel() else {
                        cancel()
                        return
                    }
                    let previousScannedHeight = lastScannedHeight
                    let scanStartTime = Date()
                    guard self.rustBackend.scanBlocks(dbCache: self.cacheDb, dbData: self.dataDb, limit: batchSize) else {
                        self.scanFailed(self.rustBackend.lastError() ?? ZcashOperationError.unknown)
                        return
                    }
                    let scanFinishTime = Date()
                    
                    lastScannedHeight = try transactionRepository.lastScannedHeight()
                    
                    scannedNewBlocks = previousScannedHeight != lastScannedHeight
                    if scannedNewBlocks {
                        let progress = BlockProgress(startHeight: scanStartHeight, targetHeight: targetScanHeight, progressHeight: lastScannedHeight)
                        progressDelegate?.progressUpdated(.scan(progress))
                        NotificationCenter.default.post(SDKMetrics.progressReportNotification(progress: progress, start: scanStartTime, end: scanFinishTime, task: .scanBlocks))
                        LoggerProxy.debug("Scanned \(lastScannedHeight - previousScannedHeight) blocks in \(scanFinishTime.timeIntervalSinceReferenceDate - scanStartTime.timeIntervalSinceReferenceDate) seconds")
                    }
                    
                } while !self.isCancelled && scannedNewBlocks && lastScannedHeight < targetScanHeight
                
            }
        } catch {
            scanFailed(error)
        }
    }
    
    func scanFailed(_ error: Error) {
        self.error = error
        LoggerProxy.debug("block scanning failed with error: \(String(describing: self.error))")
        self.fail()
    }
}
