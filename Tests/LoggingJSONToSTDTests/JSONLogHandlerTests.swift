import XCTest
import Logging
@testable import LoggingJSONToSTD

final class JSONLogHandlerTests: XCTestCase {
    
    final class InterceptStream: TextOutputStream {
        var interceptedText: String?
        var strings = [String]()

        func write(_ string: String) {
            // This is a test implementation, a real implementation would include locking
            self.strings.append(string)
            self.interceptedText = (self.interceptedText ?? "") + string
        }
    }
    
    struct LogMessage: Codable {
        let timestamp: String
        let msg: String
        let level: Logger.Level
        let metaNumber: Int
        let metaTrue: Bool
        let metaFalse: Bool
        let metaString: String
        let metaStringConvertible: String
        let metaArray: [String]
        let metaDictionary: [String: String]
    }
    
    func testJSONLogHandler() {
        
        let outputStream = InterceptStream()
        var logger = Logger(label: "test") { (label) in
            JSONLogHandler(label: label, stream: outputStream)
        }
        logger.logLevel = .info
        
        logger.info("test", metadata: [
            "metaNumber": .stringConvertible(1),
            "metaTrue": .stringConvertible(true),
            "metaFalse": .stringConvertible(false),
            "metaString": .string("meta2"),
            "metaStringConvertible": .stringConvertible("meta3"),
            "metaArray": .array([.string("1"), .string("2")]),
            "metaDictionary": .dictionary(["test1": .string("1"), "test2": .string("2")]),
        ])
        
        var string = outputStream.strings.first
        string?.removeLast()
        var logMessage: LogMessage?
        XCTAssertNoThrow(logMessage = try JSONDecoder().decode(LogMessage.self, from: XCTUnwrap(string?.data(using: .utf8))))
        
        XCTAssertEqual(logMessage?.msg, "test")
        XCTAssertEqual(logMessage?.metaNumber, 1)
        XCTAssertEqual(logMessage?.metaTrue, true)
        XCTAssertEqual(logMessage?.metaFalse, false)
        XCTAssertEqual(logMessage?.metaString, "meta2")
        XCTAssertEqual(logMessage?.metaStringConvertible, "meta3")
        XCTAssertEqual(logMessage?.metaArray.count, 2)
        XCTAssertEqual(logMessage?.metaArray, ["1", "2"])
        XCTAssertEqual(logMessage?.metaDictionary.count, 2)
        XCTAssertEqual(logMessage?.metaDictionary, ["test1": "1", "test2": "2"])
    }

}
