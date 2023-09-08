//
//  ScanActionTests.swift
//  
//
//  Created by Lukáš Korba on 18.05.2023.
//

import XCTest
@testable import TestUtils
@testable import ZcashLightClientKit

final class ScanActionTests: ZcashTestCase {
    func testScanAction_NextAction() async throws {
        let blockScannerMock = BlockScannerMock()
        let loggerMock = LoggerMock()
        
        loggerMock.debugFileFunctionLineClosure = { _, _, _, _ in }
        blockScannerMock.scanBlocksAtTotalProgressRangeDidScanClosure = { _, _, _ in 2 }

        let scanAction = setupAction(blockScannerMock, loggerMock)

        let syncContext = ActionContextMock.default()
        syncContext.lastScannedHeight = 1500
        syncContext.underlyingTotalProgressRange = 1000...2000
        syncContext.underlyingSyncControlData = SyncControlData(
            latestBlockHeight: 2000,
            latestScannedHeight: 1000,
            firstUnenhancedHeight: nil
        )

        do {
            let nextContext = try await scanAction.run(with: syncContext) { event in
                guard case .progressPartialUpdate(.syncing(let progress)) = event else {
                    XCTFail("event is expected to be .progressPartialUpdate(.syncing()) but received \(event)")
                    return
                }
                XCTAssertEqual(progress.startHeight, BlockHeight(1000))
                XCTAssertEqual(progress.targetHeight, BlockHeight(2000))
                XCTAssertEqual(progress.progressHeight, BlockHeight(1500))
            }
            XCTAssertTrue(loggerMock.debugFileFunctionLineCalled, "logger.debug(...) is expected to be called.")
            XCTAssertTrue(blockScannerMock.scanBlocksAtTotalProgressRangeDidScanCalled, "blockScanner.scanBlocks(...) is expected to be called.")
            
            let acResult = nextContext.checkStateIs(.clearAlreadyScannedBlocks)
            XCTAssertTrue(acResult == .true, "Check of state failed with '\(acResult)'")
        } catch {
            XCTFail("testScanAction_NextAction is not expected to fail. \(error)")
        }
    }
    
    func testScanAction_EarlyOutForNoDownloadAndScanRangeSet() async throws {
        let blockScannerMock = BlockScannerMock()
        let loggerMock = LoggerMock()
                
        let scanAction = setupAction(blockScannerMock, loggerMock)
        let syncContext = ActionContextMock.default()
        
        do {
            _ = try await scanAction.run(with: syncContext) { _ in }
            XCTAssertFalse(loggerMock.debugFileFunctionLineCalled, "logger.debug(...) is not expected to be called.")
            XCTAssertFalse(blockScannerMock.scanBlocksAtTotalProgressRangeDidScanCalled, "blockScanner.scanBlocks(...) is not expected to be called.")
        } catch {
            XCTFail("testScanAction_EarlyOutForNoDownloadAndScanRangeSet is not expected to fail. \(error)")
        }
    }
    
    func testScanAction_StartRangeHigherThanEndRange() async throws {
        let blockScannerMock = BlockScannerMock()
        let loggerMock = LoggerMock()

        let scanAction = setupAction(blockScannerMock, loggerMock)
        let syncContext = ActionContextMock.default()
        syncContext.lastScannedHeight = 2001
        syncContext.underlyingSyncControlData = SyncControlData(
            latestBlockHeight: 2000,
            latestScannedHeight: 1000,
            firstUnenhancedHeight: nil
        )

        do {
            _ = try await scanAction.run(with: syncContext) { _ in }
            XCTAssertFalse(loggerMock.debugFileFunctionLineCalled, "logger.debug(...) is not expected to be called.")
            XCTAssertFalse(blockScannerMock.scanBlocksAtTotalProgressRangeDidScanCalled, "blockScanner.scanBlocks(...) is not expected to be called.")
        } catch {
            XCTFail("testScanAction_StartRangeHigherThanEndRange is not expected to fail. \(error)")
        }
    }
    
    func testScanAction_EndRangeProperlySetLowerThanBatchSize() async throws {
        let blockScannerMock = BlockScannerMock()
        let loggerMock = LoggerMock()
        
        loggerMock.debugFileFunctionLineClosure = { _, _, _, _ in }
        blockScannerMock.scanBlocksAtTotalProgressRangeDidScanClosure = { _, _, _ in 2 }

        let scanAction = setupAction(blockScannerMock, loggerMock)
        let syncContext = ActionContextMock.default()
        syncContext.lastScannedHeight = 1001
        syncContext.underlyingTotalProgressRange = 1000...1078
        syncContext.underlyingSyncControlData = SyncControlData(
            latestBlockHeight: 1078,
            latestScannedHeight: 1000,
            firstUnenhancedHeight: nil
        )

        do {
            _ = try await scanAction.run(with: syncContext) { _ in }
            XCTAssertTrue(loggerMock.debugFileFunctionLineCalled, "logger.debug(...) is expected to be called.")
            XCTAssertTrue(blockScannerMock.scanBlocksAtTotalProgressRangeDidScanCalled, "blockScanner.scanBlocks(...) is expected to be called.")
            
            if let scanArguments = blockScannerMock.scanBlocksAtTotalProgressRangeDidScanReceivedArguments {
                XCTAssertEqual(scanArguments.range.upperBound, 1078)
            }
        } catch {
            XCTFail("testScanAction_EndRangeProperlySetLowerThanBatchSize is not expected to fail. \(error)")
        }
    }
    
    func testScanAction_EndRangeProperlySetBatchSize() async throws {
        let blockScannerMock = BlockScannerMock()
        let loggerMock = LoggerMock()
        
        loggerMock.debugFileFunctionLineClosure = { _, _, _, _ in }
        blockScannerMock.scanBlocksAtTotalProgressRangeDidScanClosure = { _, _, _ in 2 }

        let scanAction = setupAction(blockScannerMock, loggerMock)
        let syncContext = ActionContextMock.default()
        syncContext.lastScannedHeight = 1001
        syncContext.underlyingTotalProgressRange = 1000...1978
        syncContext.underlyingSyncControlData = SyncControlData(
            latestBlockHeight: 1978,
            latestScannedHeight: 1000,
            firstUnenhancedHeight: nil
        )

        do {
            _ = try await scanAction.run(with: syncContext) { _ in }
            XCTAssertTrue(loggerMock.debugFileFunctionLineCalled, "logger.debug(...) is expected to be called.")
            XCTAssertTrue(blockScannerMock.scanBlocksAtTotalProgressRangeDidScanCalled, "blockScanner.scanBlocks(...) is expected to be called.")
            
            if let scanArguments = blockScannerMock.scanBlocksAtTotalProgressRangeDidScanReceivedArguments {
                XCTAssertEqual(scanArguments.range.upperBound, 1101)
            }
        } catch {
            XCTFail("testScanAction_EndRangeProperlySetBatchSize is not expected to fail. \(error)")
        }
    }
    
    private func setupAction(
        _ blockScannerMock: BlockScannerMock,
        _ loggerMock: LoggerMock
    ) -> ScanAction {
        let rustBackendMock = ZcashRustBackendWeldingMock(
            consensusBranchIdForHeightClosure: { height in
                XCTAssertEqual(height, 2, "")
                return -1026109260
            }
        )

        mockContainer.mock(type: ZcashRustBackendWelding.self, isSingleton: true) { _ in rustBackendMock }
        mockContainer.mock(type: BlockScanner.self, isSingleton: true) { _ in blockScannerMock }
        mockContainer.mock(type: Logger.self, isSingleton: true) { _ in loggerMock }
        
        let config: CompactBlockProcessor.Configuration = .standard(
            for: ZcashNetworkBuilder.network(for: .testnet), walletBirthday: 0
        )
        
        return ScanAction(
            container: mockContainer,
            configProvider: CompactBlockProcessor.ConfigProvider(config: config)
        )
    }
}
