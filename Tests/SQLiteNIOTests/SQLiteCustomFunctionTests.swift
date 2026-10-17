/*

Significant portions of this file have been adapted by @danramteke
from https://github.com/groue/GRDB.swift/blob/v5.8.0/Tests/GRDBTests/DatabaseFunctionTests.swift
Here is the original copyright notice:

Copyright (C) 2015-2020 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
import SQLiteNIO
import Testing

private struct CustomValueType: SQLiteDataConvertible, Equatable {
    init() {}
    init?(sqliteData: SQLiteData) {
        guard let string = sqliteData.string, string == "CustomValueType" else {
            return nil
        }
        self = CustomValueType()
    }

    var sqliteData: SQLiteData? {
        .text("CustomValueType")
    }
}

@Suite("Database function tests")
struct DatabaseFunctionTests {
    // MARK: - Return values

    @Test
    func functionReturningNull() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in nil }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f() as result").first?.column("result")?.isNull ?? false)
        }
    }

    @Test
    func functionReturningInt64() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in 1 }
            try await conn.install(customFunction: fn)
            #expect(try await Int(1) == conn.query("SELECT f() as result").first?.column("result")?.integer)
        }
    }

    @Test
    func functionReturningDouble() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in 1e100 }

            try await conn.install(customFunction: fn)
            #expect(try await 1e100 == conn.query("SELECT f() as result").first?.column("result")?.double)
        }
    }

    @Test
    func functionReturningString() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in "foo" }

            try await conn.install(customFunction: fn)
            #expect(try await "foo" == conn.query("SELECT f() as result").first?.column("result")?.string)
        }
    }

    @Test
    func functionReturningData() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in ByteBuffer(bytes: "foo".utf8) }
            try await conn.install(customFunction: fn)

            #expect(try await ByteBuffer(string: "foo") == conn.query("SELECT f() as result").first?.column("result")?.blob)
            #expect(try await ByteBuffer(string: "bar") != conn.query("SELECT f() as result").first?.column("result")?.blob)
        }
    }

    @Test
    func functionReturningCustomValueType() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in CustomValueType() }

            try await conn.install(customFunction: fn)
            #expect(try await CustomValueType().sqliteData == conn.query("SELECT f() as result").first?.column("result"))
        }
    }

    // MARK: - Argument values

    @Test
    func functionArgumentNil() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].isNull }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.bool ?? false)
            #expect(!(try await conn.query("SELECT f(1) as result").first?.column("result")?.bool ?? true))
            #expect(!(try await conn.query("SELECT f(1.1) as result").first?.column("result")?.bool ?? true))
            #expect(!(try await conn.query("SELECT f('foo') as result").first?.column("result")?.bool ?? true))
            #expect(!(try await conn.query("SELECT f(?) as result", [.text("foo")]).first?.column("result")?.bool ?? true))
        }
    }

    @Test
    func functionArgumentInt64() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].integer }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.integer == nil)
            #expect(try await 1 == conn.query("SELECT f(1) as result").first?.column("result")?.integer)
            #expect(try await 1 == conn.query("SELECT f(1.1) as result").first?.column("result")?.integer)
        }
    }

    @Test
    func functionArgumentDouble() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].double }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.double == nil)
            #expect(try await 1.0 == conn.query("SELECT f(1) as result").first?.column("result")?.double)
            #expect(try await 1.1 == conn.query("SELECT f(1.1) as result").first?.column("result")?.double)
        }
    }

    @Test
    func functionArgumentString() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].string }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.string == nil)
            #expect(try await "foo" == conn.query("SELECT f('foo') as result").first?.column("result")?.string)
        }
    }

    @Test
    func functionArgumentBlob() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values[0].blob }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.blob == nil)
            #expect(try await ByteBuffer(string: "foo") == conn.query("SELECT f(?) as result", [.blob(ByteBuffer(string: "foo"))]).first?.column("result")?.blob)
            #expect(try await ByteBuffer() == conn.query("SELECT f(?) as result", [.blob(ByteBuffer())]).first?.column("result")?.blob)
        }
    }

    @Test
    func functionArgumentCustomValueType() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in CustomValueType(sqliteData: values[0]) }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result").flatMap(CustomValueType.init(sqliteData:)) == nil)
            #expect(try await CustomValueType() == conn.query("SELECT f('CustomValueType') as result").first?.column("result").flatMap(CustomValueType.init(sqliteData:)))
        }
    }

    // MARK: - Argument count

    @Test
    func functionWithoutArgument() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in "foo" }
            try await conn.install(customFunction: fn)

            #expect(try await "foo" == conn.query("SELECT f() as result").first?.column("result")?.string)
            let error = await #expect(throws: SQLiteError.self) { try await conn.query("SELECT f(1)") }
            #expect(error?.reason == .error)
            #expect(error?.message == "wrong number of arguments to function f()")
        }
    }

    @Test
    func functionOfOneArgument() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 1) { values in values.first?.string?.uppercased() }
            try await conn.install(customFunction: fn)

            #expect(try await conn.query("SELECT f(NULL) as result").first?.column("result")?.string == nil)
            #expect(try await "ROUé" == conn.query("SELECT upper(?) as result", [.text("Roué")]).first?.column("result")?.string)
            #expect(try await "ROUÉ" == conn.query("SELECT f(?) as result", [.text("Roué")]).first?.column("result")?.string)
            let error = await #expect(throws: SQLiteError.self) { try await conn.query("SELECT f()") }
            #expect(error?.reason == .error)
            #expect(error?.message == "wrong number of arguments to function f()")
        }
    }

    @Test
    func functionOfTwoArguments() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f", argumentCount: 2) { values in values.compactMap { $0.integer }.reduce(0, +) }
            try await conn.install(customFunction: fn)

            #expect(try await 3 == conn.query("SELECT f(1, 2) as result").first?.column("result")?.integer)
            let error = await #expect(throws: SQLiteError.self) { try await conn.query("SELECT f()") }
            #expect(error?.reason == .error)
            #expect(error?.message == "wrong number of arguments to function f()")
        }
    }

    @Test
    func variadicFunction() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f") { values in values.count }
            try await conn.install(customFunction: fn)

            #expect(try await 0 == conn.query("SELECT f() as result").first?.column("result")?.integer)
            #expect(try await 1 == conn.query("SELECT f(1) as result").first?.column("result")?.integer)
            #expect(try await 2 == conn.query("SELECT f(1, 2) as result").first?.column("result")?.integer)
            #expect(try await 3 == conn.query("SELECT f(1, 1, 1) as result").first?.column("result")?.integer)
        }
    }

    // MARK: - Errors

    @Test
    func functionThrowingDatabaseCustomErrorWithMessage() async throws {
        try await withOpenedConnection { conn in
            struct MyError: Error { let message: String }
            let fn = SQLiteCustomFunction("f") { _ in throw MyError(message: "custom message") }
            try await conn.install(customFunction: fn)

            let error = await #expect(throws: SQLiteError.self) { try await conn.query("SELECT f()") }
            #expect(error?.reason == .error)
            #expect(error?.message == "MyError(message: \"custom message\")")
        }
    }

    /*
    @Test
    func functionThrowingNSError() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("f") { _ in
                throw NSError(domain: "CustomErrorDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "custom error message", NSLocalizedFailureReasonErrorKey: "custom error message"])
            }
            try await conn.install(customFunction: fn)

            let error = try await #require(throws: SQLiteError.self) { try await conn.query("SELECT f()") }
            #expect(error.reason == .error)
            #expect(error.message.contains("CustomErrorDomain"))
            #expect(error.message.contains("123"))
            #expect(error.message.contains("custom error message"), "expected '\(error.message)' to contain 'custom error message'")
        }
    }
    */

    // MARK: - Misc

    @Test
    func functionsCanBeExtremelyUnsafeClosures() async throws {
        try await withOpenedConnection { conn in
            final class QuickBox<T: Sendable>: @unchecked Sendable { var value: T; init(_ value: T) { self.value = value } }
            let x = QuickBox(123)
            let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in x.value }
            try await conn.install(customFunction: fn)

            x.value = 321
            #expect(try await 321 == conn.query("SELECT f() as result").first?.column("result")?.integer)
        }
    }

    @Test
    func uninstallRemovesFunction() async throws {
        try await withOpenedConnection { conn in
            let fn = SQLiteCustomFunction("removable", argumentCount: 0) { values in 1 }
            try await conn.install(customFunction: fn)
            #expect(try await Int(1) == conn.query("SELECT removable() as result").first?.column("result")?.integer)

            try await conn.uninstall(customFunction: fn)

            await #expect(throws: (any Error).self) { try await conn.query("SELECT removable()") }
        }
    }

    // MARK: - setup

    init() {
        #expect(isLoggingConfigured)
    }
}
