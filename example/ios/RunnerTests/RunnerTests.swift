import XCTest

@testable import khmer_id_card_ocr

final class RunnerTests: XCTestCase {
    func testPluginClassIsLinked() {
        XCTAssertFalse(String(describing: KhmerIdCardOcrPlugin.self).isEmpty)
    }
}
