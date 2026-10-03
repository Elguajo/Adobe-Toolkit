import XCTest
import ToolkitCore
@testable import AdobeToolkit

final class AppModelTests: XCTestCase {
    @MainActor
    func testNavigationCannotStartSecondOperationAndCancelledReportAllowsRetry() async throws {
        let model = AppModel(fixtureMode: true)
        model.discover()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.available, [.backupScan, .cleanupPreview, .diagnose])
        model.run(.backupCreate)
        XCTAssertFalse(model.isBusy)

        model.run(.diagnose)
        XCTAssertTrue(model.isBusy)
        model.module = .cleanup
        model.run(.cleanupPreview)
        XCTAssertEqual(model.runningOperation, .diagnose)
        model.cancel()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.operation, "diagnose.run")
        XCTAssertEqual(model.latestReport?.status, .cancelled)
        XCTAssertNil(model.reports[.cleanupPreview])

        model.run(.cleanupPreview)
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.isSuccess, true)
        XCTAssertEqual(model.reports[.diagnose]?.status, .cancelled)
        XCTAssertEqual(model.reports[.cleanupPreview]?.isSuccess, true)
    }

    @MainActor
    private func waitUntilIdle(_ model: AppModel) async throws {
        for _ in 0..<500 where model.isBusy {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.isBusy, "Model did not release the operation lock.")
    }
}
