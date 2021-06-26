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
			throw NSError(domain: "CustomErrorDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "custom error message"])
		}

		try conn.install(customFunction: fn).wait()

		do {
			_ = try conn.query("SELECT f()").wait()
			XCTFail("Expected Error")
		} catch let error as SQLiteError {

			XCTAssertEqual(error.reason, .error)
			XCTAssertTrue(error.message.contains("CustomErrorDomain"))
			XCTAssertTrue(error.message.contains("123"))
			#if os(Linux)
			XCTAssertTrue(error.message.contains("(null)"), "expected '\(error.message)' to contain '(null)'")
			#else
			XCTAssertTrue(error.message.contains("custom error message"), "expected '\(error.message)' to contain 'custom error message'")
			#endif
		}
	}

	// MARK: - Misc

	func testFunctionsAreClosures() throws {
		let conn = try SQLiteConnection.open(storage: .memory, threadPool: self.threadPool, on: self.eventLoop).wait()
		defer { try! conn.close().wait() }

		var x = 123
		let fn = SQLiteCustomFunction("f", argumentCount: 0) { dbValues in
			return x
		}
		try conn.install(customFunction: fn).wait()
		x = 321
		XCTAssertEqual(321, try conn.query("SELECT f() as result").map({ rows in rows[0].column("result")?.integer }).wait())
	}

	// MARK: - setup

	var threadPool: NIOThreadPool!
	var eventLoopGroup: EventLoopGroup!
	var eventLoop: EventLoop {
		return self.eventLoopGroup.next()
	}

	override func setUp() {
		self.threadPool = .init(numberOfThreads: 8)
		self.threadPool.start()
		self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 8)
	}

	override func tearDown() {
		try! self.threadPool.syncShutdownGracefully()
		try! self.eventLoopGroup.syncShutdownGracefully()
	}
}
