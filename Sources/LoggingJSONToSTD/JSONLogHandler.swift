import Logging
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import MSVCRT
#else
import Glibc
#endif

/// A wrapper to facilitate `print`-ing to stderr and stdio that
/// ensures access to the underlying `FILE` is locked to prevent
/// cross-thread interleaving of output.
internal struct StdioOutputStream: TextOutputStream {
    internal let file: UnsafeMutablePointer<FILE>
    internal let flushMode: FlushMode

    internal func write(_ string: String) {
        string.withCString { ptr in
            #if os(Windows)
            _lock_file(self.file)
            #else
            flockfile(self.file)
            #endif
            defer {
                #if os(Windows)
                _unlock_file(self.file)
                #else
                funlockfile(self.file)
                #endif
            }
            _ = fputs(ptr, self.file)
            if case .always = self.flushMode {
                self.flush()
            }
        }
    }

    /// Flush the underlying stream.
    /// This has no effect when using the `.always` flush mode, which is the default
    internal func flush() {
        _ = fflush(self.file)
    }

    internal static let stderr = StdioOutputStream(file: systemStderr, flushMode: .always)
    internal static let stdout = StdioOutputStream(file: systemStdout, flushMode: .always)

    /// Defines the flushing strategy for the underlying stream.
    internal enum FlushMode {
        case undefined
        case always
    }
}

// Prevent name clashes
#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = MSVCRT.stderr
let systemStdout = MSVCRT.stdout
#else
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#endif

/// `StreamLogHandler` is a simple implementation of `LogHandler` for directing
/// `Logger` output to either `stderr` or `stdout` via the factory methods.
public struct JSONLogHandler: LogHandler {
    /// Factory that makes a `StreamLogHandler` to directs its output to `stdout`
    public static func standardOutput(label: String) -> JSONLogHandler {
        return JSONLogHandler(label: label, stream: StdioOutputStream.stdout)
    }

    /// Factory that makes a `StreamLogHandler` to directs its output to `stderr`
    public static func standardError(label: String) -> JSONLogHandler {
        return JSONLogHandler(label: label, stream: StdioOutputStream.stderr)
    }

    private let stream: TextOutputStream
    private let label: String

    public var logLevel: Logger.Level = .info

    public var metadata = Logger.Metadata()

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    // internal for testing only
    internal init(label: String, stream: TextOutputStream) {
        self.label = label
        self.stream = stream
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    file: String, function: String, line: UInt) {
        let mergedMetadata = metadata != nil
          ? self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new })
          : self.metadata
        
        let string = self.jsonify(timestamp: timestamp(), level: level, message: message, metadata: mergedMetadata)
      
        var stream = self.stream
        stream.write(string)
    }

    private func jsonify(timestamp: String,
                         level: Logger.Level,
                         message: Logger.Message,
                         metadata: Logger.Metadata) -> String
    {
        var bytes = [UInt8]()
        bytes.reserveCapacity(1024)
        bytes.append(contentsOf: #"{"timestamp":""#.utf8)
        bytes.append(contentsOf: timestamp.utf8)
        bytes.append(contentsOf: #"","level":""#.utf8)
        bytes.append(contentsOf: level.rawValue.utf8)
        bytes.append(UInt8(ascii: "\""))
        
        var iterator = metadata.makeIterator()
        while let (key, value) = iterator.next() {
            bytes.append(UInt8(ascii: ","))
            Logger.MetadataValue.encodeString(key, to: &bytes)
            bytes.append(UInt8(ascii: ":"))
            value.appendBytes(to: &bytes)
        }
        
        bytes.append(contentsOf: #","msg":""#.utf8)
        bytes.append(contentsOf: message.description.utf8)
        
        bytes.append(contentsOf: "\"}\n".utf8)
//        bytes.append(UInt8(ascii: ""))
        
        return String(decoding: bytes, as: Unicode.UTF8.self)
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}


extension Logger.MetadataValue {
    func appendBytes(to bytes: inout [UInt8]) {
        switch self {
        case .array(let array):
            var iterator = array.makeIterator()
            bytes.append(UInt8(ascii: "["))
            // we don't kine branching, this is why we have this extra
            if let first = iterator.next() {
              first.appendBytes(to: &bytes)
            }
            while let item = iterator.next() {
              bytes.append(UInt8(ascii: ","))
              item.appendBytes(to: &bytes)
            }
            bytes.append(UInt8(ascii: "]"))
        case .dictionary(let dict):
            var iterator = dict.makeIterator()
            bytes.append(UInt8(ascii: "{"))
            if let (key, value) = iterator.next() {
                Self.encodeString(key, to: &bytes)
                bytes.append(UInt8(ascii: ":"))
                value.appendBytes(to: &bytes)
            }
            while let (key, value) = iterator.next() {
                bytes.append(UInt8(ascii: ","))
                Self.encodeString(key, to: &bytes)
                bytes.append(UInt8(ascii: ":"))
                value.appendBytes(to: &bytes)
            }
            bytes.append(UInt8(ascii: "}"))
        case .string(let string):
            Self.encodeString(string, to: &bytes)
        case .stringConvertible(let convertible as Bool):
            switch convertible {
            case true:
                bytes.append(contentsOf: "true".utf8)
            case false:
                bytes.append(contentsOf: "false".utf8)
            }
        case .stringConvertible(let convertible) where convertible is AnyNumeric:
            bytes.append(contentsOf: convertible.description.utf8)
        case .stringConvertible(let convertible): // fallback
            Self.encodeString(convertible.description, to: &bytes)
        }
    }

    static func encodeString(_ string: String, to bytes: inout [UInt8]) {
        bytes.append(UInt8(ascii: "\""))
        let stringBytes    = string.utf8
        var startCopyIndex = stringBytes.startIndex
        var nextIndex      = startCopyIndex
        
        while nextIndex != stringBytes.endIndex {
            switch stringBytes[nextIndex] {
            case 0..<32, UInt8(ascii: "\""), UInt8(ascii: "\\"):
                // All Unicode characters may be placed within the
                // quotation marks, except for the characters that MUST be escaped:
                // quotation mark, reverse solidus, and the control characters (U+0000
                // through U+001F).
                // https://tools.ietf.org/html/rfc7159#section-7
            
                // copy the current range over
                bytes.append(contentsOf: stringBytes[startCopyIndex..<nextIndex])
                bytes.append(UInt8(ascii: "\\"))
                bytes.append(stringBytes[nextIndex])
            
                nextIndex      = stringBytes.index(after: nextIndex)
                startCopyIndex = nextIndex
            default:
                nextIndex      = stringBytes.index(after: nextIndex)
            }
        }
        
        // copy everything, that hasn't been copied yet
        bytes.append(contentsOf: stringBytes[startCopyIndex..<nextIndex])
        bytes.append(UInt8(ascii: "\""))
    }
}

// HACK: This is so ugly, I can't believe it myself.
protocol AnyNumeric: CustomStringConvertible {}
extension Int8: AnyNumeric {}
extension Int16: AnyNumeric {}
extension Int32: AnyNumeric {}
extension Int64: AnyNumeric {}
extension UInt8: AnyNumeric {}
extension UInt16: AnyNumeric {}
extension UInt32: AnyNumeric {}
extension UInt64: AnyNumeric {}
extension Int: AnyNumeric {}
extension UInt: AnyNumeric {}
extension Float: AnyNumeric {}
extension Double: AnyNumeric {}
