#if canImport(Darwin)

import Foundation

struct AsyncNotOmittingEmptySubsequencesLineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String
    var base: Base
    struct AsyncIterator: AsyncIteratorProtocol {
        var src: Base.AsyncIterator, buf: Array<UInt8> = [], save: UInt8? = nil

        @_specialize(where Base == FileHandle.AsyncBytes)
        @_specialize(where Base == URL.AsyncBytes)
        mutating func next() async rethrows -> String? {
            let _CR:   UInt8 = 0x0D, _LF:   UInt8 = 0x0A
            let _NEL1: UInt8 = 0xC2, _NEL2: UInt8 = 0x85
            let _SEP1: UInt8 = 0xE2, _SEP2: UInt8 = 0x80, _SEP3L: UInt8 = 0xA8, _SEP3P: UInt8 = 0xA9

            func yield() -> String? {
                defer { buf.removeAll(keepingCapacity: true) }
                return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self)
            }
            func nextByte() async throws -> UInt8? {
                defer { save = nil }
                if let save { return save }
                else { return try await src.next() }
            }
            
            while let first = try await nextByte() {
                switch first {
                case _CR:
                    if let next = try await src.next(), next != _LF { save = next }
                case _LF: break
                case _NEL1:
                    guard let next = try await src.next() else { buf.append(first); break }
                    guard next == _NEL2                   else { buf.append(contentsOf: [first, next]); continue }
                case _SEP1:
                    guard let next = try await src.next() else { buf.append(first); break }
                    guard next == _SEP2                   else { buf.append(contentsOf: [first, next]); continue }
                    guard let fin = try await src.next()  else { buf.append(contentsOf: [first, next]); break }
                    guard fin == _SEP3L || fin == _SEP3P  else { buf.append(contentsOf: [first, next, fin]); continue }
                default: buf.append(first); continue
                }
                return yield() ?? ""
            }
            return yield()
        }
    }
    func makeAsyncIterator() -> AsyncIterator { .init(src: base.makeAsyncIterator()) }
}

extension AsyncSequence where Self.Element == UInt8 {
    var keepingEmptySubsequencesLines: AsyncNotOmittingEmptySubsequencesLineSequence<Self> { .init(base: self) }
}

#endif
