#if canImport(NIOCore)
@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer
@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup
@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
#else  // !canImport(NIOCore)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// `BLOB` values are carried by `[UInt8]` on platforms where SwiftNIO is not available.
///
/// SwiftNIO does not support `wasm32-unknown-wasip1`, so `NIOCore.ByteBuffer` cannot be re-exported
/// above (see the product conditions in `Package.swift`). Declaring the substitution as a typealias
/// rather than forking every declaration that mentions `ByteBuffer` keeps ``SQLiteData`` and friends
/// as a single implementation across both configurations.
public typealias ByteBuffer = [UInt8]

/// The subset of `NIOCore.ByteBuffer`'s API that this package uses, expressed over `[UInt8]`.
///
/// These are deliberately not `public`: they exist only so the shared implementation compiles
/// unchanged, and making them public would graft NIO-flavored members onto every `[UInt8]` in any
/// module that imports `SQLiteNIO`.
extension ByteBuffer {
    init(bytes: some Sequence<UInt8>) {
        self.init(bytes)
    }

    init(data: Data) {
        self.init(data)
    }

    var readableBytes: Int {
        self.count
    }

    var readableBytesView: Self {
        self
    }

    func withUnsafeReadableBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        try self.withUnsafeBytes(body)
    }
}

// N.B.: A tripwire, not a platform gate. The stand-in below takes no lock, so it only supports
// single-threaded use: `wasm32-unknown-wasip1` qualifies, `wasm32-unknown-wasip1-threads` does not.
#if _runtime(_multithreaded)
#error("""
    SQLiteNIO's `canImport(NIOCore)` fallback has been selected for a multithreaded runtime, and the \
    `NIOLockedValueBox` below does not support multithreaded locking. Please use a \
    multithreading-capable lock for this platform.
    """)
#endif

/// A single-threaded stand-in for `NIOConcurrencyHelpers.NIOLockedValueBox`.
///
/// The one supported SwiftNIO-free target is single-threaded, so no lock is needed and none is
/// taken: the box exists so the `sqlite3_initialize()` guard and the hook observer storage in
/// ``SQLiteConnection`` read the same in both configurations. `@unchecked Sendable` is sound for
/// the same reason.
final class NIOLockedValueBox<Value>: @unchecked Sendable {
    private var value: Value
    private var isLocked = false

    init(_ value: Value) {
        self.value = value
    }

    func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        assert(!self.isLocked, "NIOLockedValueBox was re-entered unexpectedly; this implementation supports single-threaded use only")
        self.isLocked = true
        defer { self.isLocked = false }
        return try mutate(&self.value)
    }
}
#endif  // !canImport(NIOCore)
