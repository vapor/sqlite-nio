import CSQLite

/// An SQL function or aggregate.
public final class SQLiteCustomFunction: Hashable {
	// SQLite identifies functions by (name + argument count)
	private struct Identity: Hashable {
		let name: String
		let nArg: Int32 // -1 for variadic functions
	}

	/// The name of the SQL function
	public var name: String { identity.name }
	private let identity: Identity
	let pure: Bool
	private let kind: Kind
	private var eTextRep: Int32 { (SQLITE_UTF8 | (pure ? SQLITE_DETERMINISTIC : 0)) }

	public init(
		_ name: String,
		argumentCount: Int32? = nil,
		pure: Bool = false,
		function: @escaping ([SQLiteData]) throws -> SQLiteDataConvertible?)
	{
		self.identity = Identity(name: name, nArg: argumentCount ?? -1)
		self.pure = pure
		self.kind = .function { (argc, argv) in
			let arguments = (0..<Int(argc)).map { index -> SQLiteData in
				return SQLiteData(sqliteValue: argv.unsafelyUnwrapped[index]!)
			}
			return try function(arguments)
		}
	}

	/// Creates an SQL aggregate function.
	///
	/// For example:
	///
	///     struct MySum: SQLiteCustomAggregate {
	///         var sum: Int = 0
	///
	///         mutating func step(_ values: [SQLiteData]) {
	///             if let int = dbValues[0].integer {
	///                 sum += int
	///             }
	///         }
	///
	///         func finalize() -> SQLiteDataConvertible? {
	///             return sum
	///         }
	///     }
	///
	///     let connection: SQLiteConnection = ...
	///     let fn = SQLiteCustomFunction("mysum", argumentCount: 1, aggregate: MySum.self)
	///     fn.install(in: connection)
	///     try connection.query("CREATE TABLE test(i)").wait()
	///     try connection.query("INSERT INTO test(i) VALUES (1)").wait()
	///     try connection.query("INSERT INTO test(i) VALUES (2)").wait()
	///     try connection.query("SELECT mysum(i) FROM test").wait()! // 3
	///     }
	///
	/// - parameters:
	///     - name: The function name.
	///     - argumentCount: The number of arguments of the aggregate. If
	///       omitted, or nil, the aggregate accepts any number of arguments.
	///     - pure: Whether the aggregate is "pure", which means that its
	///       results only depends on its inputs. When an aggregate is pure,
	///       SQLite has the opportunity to perform additional optimizations.
	///       Default value is false.
	///     - aggregate: A type that implements the DatabaseAggregate protocol.
	///       For each step of the aggregation, its `step` method is called with
	///       an array of DatabaseValue arguments. The array is guaranteed to
	///       have exactly *argumentCount* elements, provided *argumentCount* is
	///       not nil.
	public init<Aggregate: SQLiteCustomAggregate>(
		_ name: String,
		argumentCount: Int32? = nil,
		pure: Bool = false,
		aggregate: Aggregate.Type)
	{
		self.identity = Identity(name: name, nArg: argumentCount ?? -1)
		self.pure = pure
		self.kind = .aggregate { Aggregate() }
	}

	/// Calls sqlite3_create_function_v2
	/// See https://sqlite.org/c3ref/create_function.html
	func install(in connection: SQLiteConnection) throws {
		// Retain the function definition
		let definition = kind.definition
		let definitionP = Unmanaged.passRetained(definition).toOpaque()

		let code = sqlite3_create_function_v2(
			connection.handle,
			identity.name,
			identity.nArg,
			eTextRep,
			definitionP,
			kind.xFunc,
			kind.xStep,
			kind.xFinal,
			{ definitionP in
				// Release the function definition
				Unmanaged<AnyObject>.fromOpaque(definitionP!).release()
			})

		guard code == SQLITE_OK else {
			// Assume a bug: there is no point throwing any error.
			throw SQLiteError(statusCode: code, connection: connection)
		}
	}
	/// Calls sqlite3_create_function_v2
	/// See https://sqlite.org/c3ref/create_function.html
	func uninstall(in connection: SQLiteConnection) throws {
		let code = sqlite3_create_function_v2(
			connection.handle,
			identity.name,
			identity.nArg,
			eTextRep,
			nil, nil, nil, nil, nil)

		guard code == SQLITE_OK else {
			// Assume a bug: there is no point throwing any error.
			throw SQLiteError(statusCode: code, connection: connection)
		}
	}

	/// The way to compute the result of a function.
	/// Feeds the `pApp` parameter of sqlite3_create_function_v2
	/// http://sqlite.org/capi3ref.html#sqlite3_create_function
	private class FunctionDefinition {
		let compute: (Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> SQLiteDataConvertible?
		init(compute: @escaping (Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> SQLiteDataConvertible?) {
			self.compute = compute
		}
	}

	/// The way to start an aggregate.
	/// Feeds the `pApp` parameter of sqlite3_create_function_v2
	/// http://sqlite.org/capi3ref.html#sqlite3_create_function
	private class AggregateDefinition {
		let makeAggregate: () -> SQLiteCustomAggregate
		init(makeAggregate: @escaping () -> SQLiteCustomAggregate) {
			self.makeAggregate = makeAggregate
		}
	}

	/// The current state of an aggregate, storable in SQLite
	private class AggregateContext {
		var aggregate: SQLiteCustomAggregate
		var hasErrored = false
		init(aggregate: SQLiteCustomAggregate) {
			self.aggregate = aggregate
		}
	}

	/// A function kind: an "SQL function" or an "aggregate".
	/// See http://sqlite.org/capi3ref.html#sqlite3_create_function
	private enum Kind {
		/// A regular function: SELECT f(1)
		case function((Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> SQLiteDataConvertible?)

		/// An aggregate: SELECT f(foo) FROM bar GROUP BY baz
		case aggregate(() -> SQLiteCustomAggregate)

		/// Feeds the `pApp` parameter of sqlite3_create_function_v2
		/// http://sqlite.org/capi3ref.html#sqlite3_create_function
		var definition: AnyObject {
			switch self {
			case .function(let compute):
				return FunctionDefinition(compute: compute)
			case .aggregate(let makeAggregate):
				return AggregateDefinition(makeAggregate: makeAggregate)
			}
		}

		/// Feeds the `xFunc` parameter of sqlite3_create_function_v2
		/// http://sqlite.org/capi3ref.html#sqlite3_create_function
		var xFunc: (@convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void)? {
			guard case .function = self else { return nil }
			return { (sqliteContext, argc, argv) in
				let definition = Unmanaged<FunctionDefinition>
					.fromOpaque(sqlite3_user_data(sqliteContext))
					.takeUnretainedValue()
				do {
					try SQLiteCustomFunction.report(
						result: definition.compute(argc, argv),
						in: sqliteContext)
				} catch {
					SQLiteCustomFunction.report(error: error, in: sqliteContext)
				}
			}
		}

		/// Feeds the `xStep` parameter of sqlite3_create_function_v2
		/// http://sqlite.org/capi3ref.html#sqlite3_create_function
		var xStep: (@convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void)? {
			guard case .aggregate = self else { return nil }
			return { (sqliteContext, argc, argv) in
				let aggregateContextU = SQLiteCustomFunction.unmanagedAggregateContext(sqliteContext)
				let aggregateContext = aggregateContextU.takeUnretainedValue()
				assert(!aggregateContext.hasErrored) // assert SQLite behavior
				do {
					let arguments = (0..<Int(argc)).map { index in
						SQLiteData(sqliteValue: argv.unsafelyUnwrapped[index]!)
					}
					try aggregateContext.aggregate.step(arguments)
				} catch {
					aggregateContext.hasErrored = true
					SQLiteCustomFunction.report(error: error, in: sqliteContext)
				}
			}
		}

		/// Feeds the `xFinal` parameter of sqlite3_create_function_v2
		/// http://sqlite.org/capi3ref.html#sqlite3_create_function
		var xFinal: (@convention(c) (OpaquePointer?) -> Void)? {
			guard case .aggregate = self else { return nil }
			return { (sqliteContext) in
				let aggregateContextU = SQLiteCustomFunction.unmanagedAggregateContext(sqliteContext)
				let aggregateContext = aggregateContextU.takeUnretainedValue()
				aggregateContextU.release()

				guard !aggregateContext.hasErrored else {
					return
				}

				do {
					try SQLiteCustomFunction.report(
						result: aggregateContext.aggregate.finalize(),
						in: sqliteContext)
				} catch {
					SQLiteCustomFunction.report(error: error, in: sqliteContext)
				}
			}
		}
	}

	/// Helper function that extracts the current state of an aggregate from an
	/// sqlite function execution context.
	///
	/// The result must be released when the aggregate concludes.
	///
	/// See https://sqlite.org/c3ref/context.html
	/// See https://sqlite.org/c3ref/aggregate_context.html
	private static func unmanagedAggregateContext(_ sqliteContext: OpaquePointer?) -> Unmanaged<AggregateContext> {
		// > The first time the sqlite3_aggregate_context(C,N) routine is called
		// > for a particular aggregate function, SQLite allocates N of memory,
		// > zeroes out that memory, and returns a pointer to the new memory.
		// > On second and subsequent calls to sqlite3_aggregate_context() for
		// > the same aggregate function instance, the same buffer is returned.
		let stride = MemoryLayout<Unmanaged<AggregateContext>>.stride
		let aggregateContextBufferP = UnsafeMutableRawBufferPointer(
			start: sqlite3_aggregate_context(sqliteContext, Int32(stride))!,
			count: stride)

		if aggregateContextBufferP.contains(where: { $0 != 0 }) {
			// Buffer contains non-zero byte: load aggregate context
			let aggregateContextP = aggregateContextBufferP
				.baseAddress!
				.assumingMemoryBound(to: Unmanaged<AggregateContext>.self)
			return aggregateContextP.pointee
		} else {
			// Buffer contains null pointer: create aggregate context.
			let aggregate = Unmanaged<AggregateDefinition>.fromOpaque(sqlite3_user_data(sqliteContext))
				.takeUnretainedValue()
				.makeAggregate()
			let aggregateContext = AggregateContext(aggregate: aggregate)

			// retain and store in SQLite's buffer
			let aggregateContextU = Unmanaged.passRetained(aggregateContext)
			let aggregateContextP = aggregateContextU.toOpaque()
			withUnsafeBytes(of: aggregateContextP) {
				aggregateContextBufferP.copyMemory(from: $0)
			}
			return aggregateContextU
		}
	}

	private static func report(result: SQLiteDataConvertible?, in sqliteContext: OpaquePointer?) {
		switch result?.sqliteData ?? .null {
		case .null:
			sqlite3_result_null(sqliteContext)
		case .integer(let int64):
			sqlite3_result_int64(sqliteContext, Int64(int64))
		case .float(let double):
			sqlite3_result_double(sqliteContext, double)
		case .text(let string):
			sqlite3_result_text(sqliteContext, string, -1, SQLITE_TRANSIENT)
		case .blob(let value):
			value.withUnsafeReadableBytes { pointer in
				sqlite3_result_blob(sqliteContext, pointer.baseAddress, Int32(value.readableBytes), SQLITE_TRANSIENT)
			}
		}
	}

	private static func report(error: Error, in sqliteContext: OpaquePointer?) {
		if let error = error as? SQLiteError {
			sqlite3_result_error(sqliteContext, error.message, -1)
			sqlite3_result_error_code(sqliteContext, error.reason.statusCode)
		} else {
			sqlite3_result_error(sqliteContext, "\(error)", -1)
		}
	}
}

extension SQLiteCustomFunction {
	/// :nodoc:
	public func hash(into hasher: inout Hasher) {
		hasher.combine(identity)
	}

	/// Two functions are equal if they share the same name and arity.
	/// :nodoc:
	public static func == (lhs: SQLiteCustomFunction, rhs: SQLiteCustomFunction) -> Bool {
		lhs.identity == rhs.identity
	}
}

/// The protocol for custom SQLite aggregates.
///
/// For example:
///
///     struct MySum : DatabaseAggregate {
///         var sum: Int = 0
///
///         mutating func step(_ dbValues: [DatabaseValue]) {
///             if let int = Int.fromDatabaseValue(dbValues[0]) {
///                 sum += int
///             }
///         }
///
///         func finalize() -> DatabaseValueConvertible? {
///             return sum
///         }
///     }
///
///     let connection: SQLiteConnection = ...
///     let fn = SQLiteCustomFunction("mysum", argumentCount: 1, aggregate: MySum.self)
///     try connection.install(customFunction: fn).wait()
///     try connection.query("CREATE TABLE test(i)").wait()
///     try connection.query("INSERT INTO test(i) VALUES (1)").wait()
///     try connection.query("INSERT INTO test(i) VALUES (2)").wait()
///     let sum: Int = try connection.query("SELECT mysum(i) FROM test")!.wait()
public protocol SQLiteCustomAggregate {
	/// Creates an aggregate.
	init()

	/// This method is called at each step of the aggregation.
	///
	/// The dbValues argument contains as many values as given to the SQL
	/// aggregate function.
	///
	///    -- One value
	///    SELECT maxLength(name) FROM player
	///
	///    -- Two values
	///    SELECT maxFullNameLength(firstName, lastName) FROM player
	///
	/// This method is never called after the finalize() method has been called.
	mutating func step(_ values: [SQLiteData]) throws

	/// Returns the final result
	func finalize() throws -> SQLiteDataConvertible?
}
