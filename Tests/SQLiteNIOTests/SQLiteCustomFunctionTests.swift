/*

Significant portions of this file have been adapted by @danramteke 
from https://github.com/groue/GRDB.swift/blob/v5.8.0/Tests/GRDBTests/DatabaseFunctionTests.swift
Here is the original copyright notice:

Copyright (C) 2015-2020 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
import XCTest
import SQLiteNIO

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

class DatabaseFunctionTests: XCTestCase {

	// MARK: - Return values

	func testFunctionReturningNull() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			return nil
		}
		try conn.install(customFunction: fn).wait()

		XCTAssertTrue(try conn.query("SELECT f() as result").map { rows in rows[0].column("result")!.isNull }.wait())
	}

	func testFunctionReturningInt64() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			return Int(1)
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertEqual(Int(1), try conn.query("SELECT f() as result").map { rows in rows[0].column("result")?.integer }.wait())
	}

	func testFunctionReturningDouble() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			return 1e100
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertEqual(1e100, try conn.query("SELECT f() as result").map { rows in rows[0].column("result")?.double }.wait())
	}

	func testFunctionReturningString() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in
			return "foo"
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertEqual("foo", try conn.query("SELECT f() as result").map { rows in rows[0].column("result")?.string }.wait())
	}

	func testFunctionReturningData() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { values in
			return "foo".data(using: .utf8)
		}
		try conn.install(customFunction: fn).wait()

		XCTAssertEqual("foo".data(using: .utf8)!.sqliteData!.blob!,
									 try conn.query("SELECT f() as result").map { rows in rows[0].column("result")?.blob }.wait())

		XCTAssertNotEqual("bar".data(using: .utf8)!.sqliteData!.blob!,
									 try conn.query("SELECT f() as result").map { rows in rows[0].column("result")?.blob }.wait())
	}

	func testFunctionReturningCustomValueType() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			return CustomValueType()
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertEqual(CustomValueType().sqliteData, try conn.query("SELECT f() as result").map { rows in rows[0].column("result") }.wait())
	}

	// MARK: - Argument values

	func testFunctionArgumentNil() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values[0].isNull
		}
		try conn.install(customFunction: fn).wait()

		XCTAssertTrue(try conn.query("SELECT f(NULL) as result")
										.map { rows in rows[0].column("result")!.bool! }.wait())
		XCTAssertFalse(try conn.query("SELECT f(1) as result")
										.map { rows in rows[0].column("result")!.bool! }.wait())
		XCTAssertFalse(try conn.query("SELECT f(1.1) as result")
										.map { rows in rows[0].column("result")!.bool! }.wait())
		XCTAssertFalse(try conn.query("SELECT f('foo') as result")
										.map { rows in rows[0].column("result")!.bool! }.wait())
		XCTAssertFalse(try conn.query("SELECT f(?) as result", [.text("foo")])
										.map { rows in rows[0].column("result")!.bool! }.wait())
	}

	func testFunctionArgumentInt64() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values[0].integer
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
		XCTAssertEqual(1, try conn.query("SELECT f(1) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
		XCTAssertEqual(1, try conn.query("SELECT f(1.1) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
	}

	func testFunctionArgumentDouble() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values[0].double
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
									.map { rows in rows[0].column("result")?.double }.wait())
		XCTAssertEqual(1.0, try conn.query("SELECT f(1) as result")
										.map { rows in rows[0].column("result")?.double }.wait())
		XCTAssertEqual(1.1, try conn.query("SELECT f(1.1) as result")
										.map { rows in rows[0].column("result")?.double }.wait())
	}

	func testFunctionArgumentString() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values[0].string
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
									.map { rows in rows[0].column("result")?.string }.wait())
		XCTAssertEqual("foo", try conn.query("SELECT f('foo') as result")
										.map { rows in rows[0].column("result")?.string }.wait())
	}

	func testFunctionArgumentBlob() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values[0].blob
		}
		try conn.install(customFunction: fn).wait()

		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
									.map { rows in rows[0].column("result")?.blob }.wait())

		XCTAssertEqual("foo".data(using: .utf8)!.sqliteData!.blob, try conn.query("SELECT f(?) as result", ["foo".data(using: .utf8)!.sqliteData!])
									.map { rows in rows[0].column("result")?.blob }.wait())

		XCTAssertEqual(ByteBuffer(), try conn.query("SELECT f(?) as result", [.blob(ByteBuffer())])
										.map { rows in rows[0].column("result")?.blob }.wait())
	}

	func testFunctionArgumentCustomValueType() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return CustomValueType(sqliteData: values[0])
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
									.map { rows in CustomValueType(sqliteData: rows[0].column("result")!) }.wait())
		XCTAssertEqual(CustomValueType(), try conn.query("SELECT f('CustomValueType') as result")
										.map { rows in CustomValueType(sqliteData: rows[0].column("result")!)  }.wait())
	}

	// MARK: - Argument count

	func testFunctionWithoutArgument() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { (values: [SQLiteData]) in
			return "foo"
		}
		try conn.install(customFunction: fn).wait()
		XCTAssertEqual("foo", try conn.query("SELECT f() as result")
										.map { rows in rows[0].column("result")?.string }.wait())

		do {
			_ = try conn.query("SELECT f(1)").wait()
		} catch let error as SQLiteError {
			XCTAssertEqual(error.reason, .error)
			XCTAssertEqual(error.message, "wrong number of arguments to function f()")
		}
	}

	func testFunctionOfOneArgument() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f", argumentCount: 1) { (values: [SQLiteData]) in
			return values.first?.string?.uppercased()
		}

		try conn.install(customFunction: fn).wait()

		XCTAssertNil(try conn.query("SELECT f(NULL) as result")
									.map { rows in rows[0].column("result")?.string }.wait())
		XCTAssertEqual("ROUé", try conn.query("SELECT upper(?) as result", [.text("Roué")])
										.map { rows in rows[0].column("result")?.string }.wait())
		XCTAssertEqual("ROUÉ", try conn.query("SELECT f(?) as result", [.text("Roué")])
										.map { rows in rows[0].column("result")?.string }.wait())

		do {
			_ = try conn.query("SELECT f()").wait()
		} catch let error as SQLiteError {
			XCTAssertEqual(error.reason, .error)
			XCTAssertEqual(error.message, "wrong number of arguments to function f()")
		}
	}

	func testFunctionOfTwoArguments() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		let fn = SQLiteCustomFunction("f", argumentCount: 2) { (values: [SQLiteData]) in
			values
				.compactMap { $0.integer }
				.reduce(0, +)
		}

		try conn.install(customFunction: fn).wait()
		XCTAssertEqual(3, try conn.query("SELECT f(1, 2) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())

		do {
			_ = try conn.query("SELECT f()").wait()
		} catch let error as SQLiteError {
			XCTAssertEqual(error.reason, .error)
			XCTAssertEqual(error.message, "wrong number of arguments to function f()")
		}
	}

	func testVariadicFunction() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		let fn = SQLiteCustomFunction("f") { (values: [SQLiteData]) in
			values.count
		}
		try conn.install(customFunction: fn).wait()

		XCTAssertEqual(0, try conn.query("SELECT f() as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
		XCTAssertEqual(1, try conn.query("SELECT f(1) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
		XCTAssertEqual(2, try conn.query("SELECT f(1, 2) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
		XCTAssertEqual(3, try conn.query("SELECT f(1, 1, 1) as result")
										.map { rows in rows[0].column("result")?.integer }.wait())
	}

	// MARK: - Errors

	func testFunctionThrowingDatabaseCustomErrorWithMessage() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		struct MyError: Error {
			let message: String
		}

		let fn = SQLiteCustomFunction("f") { _ in
			throw MyError(message: "custom message")
		}

		try conn.install(customFunction: fn).wait()

		do {
			_ = try conn.query("SELECT f()").wait()
			XCTFail("Expected Error")
		} catch let error as MyError {
			XCTFail("expected this not to match")
			XCTAssertEqual(error.message, "custom message")
		} catch let error as SQLiteError {

			XCTAssertEqual(error.reason, .error)
			XCTAssertEqual(error.message, "MyError(message: \"custom message\")")
		}
	}

	func testFunctionThrowingNSError() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
		let fn = SQLiteCustomFunction("f") { _ in
			throw NSError(domain: "CustomErrorDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "custom error message", NSLocalizedFailureReasonErrorKey: "custom error message"])
		}

		try conn.install(customFunction: fn).wait()

		do {
			_ = try conn.query("SELECT f()").wait()
			XCTFail("Expected Error")
		} catch let error as SQLiteError {
			XCTAssertEqual(error.reason, .error)
			XCTAssertTrue(error.message.contains("CustomErrorDomain"))
			XCTAssertTrue(error.message.contains("123"))
			XCTAssertTrue(error.message.contains("custom error message"), "expected '\(error.message)' to contain 'custom error message'")
		}
	}

	// MARK: - Misc

	func testFunctionsAreClosures() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }
        
        final class QuickBox<T: Sendable>: @unchecked Sendable {
            var value: T
            init(_ value: T) { self.value = value }
        }
		let x = QuickBox(123)
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			x.value
		}
		try conn.install(customFunction: fn).wait()
		x.value = 321
		XCTAssertEqual(321, try conn.query("SELECT f() as result").map({ rows in rows[0].column("result")?.integer }).wait())
	}

	// MARK: - setup

	var threadPool: NIOThreadPool!
	var eventLoopGroup: (any EventLoopGroup)!
	var eventLoop: any EventLoop {
		return self.eventLoopGroup.any()
	}

	override func setUp() {
		self.threadPool = .init(numberOfThreads: 1)
		self.threadPool.start()
		self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
	}

	override func tearDown() {
		try! self.threadPool.syncShutdownGracefully()
		try! self.eventLoopGroup.syncShutdownGracefully()
	}
}
