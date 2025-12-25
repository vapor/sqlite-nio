/*

Significant portions of this file have been adapted by @danramteke 
from https://github.com/groue/GRDB.swift/blob/v5.8.0/GRDB/Core/DatabaseFunction.swift
Here is the original copyright notice:

Copyright (C) 2015-2020 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
#if SQLCipher
import CSQLCipher
#else
import CSQLite
#endif

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
    private let pure: Bool
    private let indirect: Bool
    private let kind: Kind
    private var eTextRep: Int32 { (SQLITE_UTF8 | (pure ? SQLITE_DETERMINISTIC : 0) | (indirect ? 0 : SQLITE_DIRECTONLY)) }

    public struct SQLiteCustomFunctionArgumentError: Error {
        public let count: Int
        public let index: Int
    }
  
    public init(
        _ name: String,
        argumentCount: Int32? = nil,
        pure: Bool = false,
        indirect: Bool = false,
        function: @Sendable @escaping ([SQLiteData]) throws -> (any SQLiteDataConvertible)?)
    {
        self.identity = Identity(name: name, nArg: argumentCount ?? -1)
        self.pure = pure
        self.indirect = indirect
        self.kind = .function { (argc, argv) in
            try function((0 ..< Int(argc)).map { index -> SQLiteData in
                guard let value = argv?[index] else {
                    throw SQLiteCustomFunctionArgumentError(count: Int(argc), index: index)
                }
                return try SQLiteData(sqliteValue: value)
            })
        }
    }

    /// Creates an SQL aggregate function.
    ///
    /// For example:
    ///
    ///     struct MySum: DatabaseAggregate {
    ///         var sum: Int = 0
    ///
    ///         mutating func step(_ dbValues: [SQLiteData]) {
    ///             sum += dbValues[0].integer ?? 0
    ///         }
    ///
    ///         func finalize() -> (any SQLiteDataConvertible)? {
    ///             sum
    ///         }
    ///     }
    ///
    ///     let connection: SQLiteConnection = ...
    ///     let fn = SQLiteCustomFunction("mysum", argumentCount: 1, pure: true, aggregate: MySum.self)
    ///     try await connection.install(customFunction: fn).get()
    ///     try await connection.query("CREATE TABLE test(i)").get()
    ///     try await connection.query("INSERT INTO test(i) VALUES (1)").get()
    ///     try await connection.query("INSERT INTO test(i) VALUES (2)").get()
    ///     let sum = (try await connection.query("SELECT mysum(i) FROM test").get().first?.columns.first?.integer)! // 3
    ///
    /// - Parameters:
    ///   - name: The function name.
    ///   - argumentCount: The number of arguments of the aggregate. If
    ///     omitted, or nil, the aggregate accepts any number of arguments.
    ///   - pure: Whether the aggregate is "pure", which means that its
    ///     results only depends on its inputs. When an aggregate is pure,
    ///     SQLite has the opportunity to perform additional optimizations.
    ///     Default value is false.
    ///   - aggregate: A type that implements the ``SQLiteCustomAggregate`` protocol.
    ///     For each step of the aggregation, its ``SQLiteCustomAggregate/step(_:)``
    ///     method is called with an array of DatabaseValue arguments. The array
    ///     is guaranteed to have exactly `argumentCount` elements, provided
    ///     `argumentCount` is not nil.
    public init<Aggregate: SQLiteCustomAggregate>(
        _ name: String,
        argumentCount: Int32? = nil,
        pure: Bool = false,
        indirect: Bool = false,
        aggregate: Aggregate.Type
    ) {
        self.identity = Identity(name: name, nArg: argumentCount ?? -1)
        self.pure = pure
        self.indirect = indirect
        self.kind = .aggregate { aggregate.init() }
    }

    /// Invokes `sqlite3_create_function_v2()` to install a custom function.
    /// See https://sqlite.org/c3ref/create_function.html
    func install(in connection: SQLiteConnection) throws {
        // Retain the function definition
        let code = sqlite_nio_sqlite3_create_function_v2(
            connection.handle.raw,
            self.identity.name,
            self.identity.nArg,
            self.eTextRep,
            Unmanaged.passRetained(self.kind.definition).toOpaque(),
            self.kind.xFunc,
            self.kind.xStep,
            self.kind.xFinal,
            { Unmanaged<AnyObject>.fromOpaque($0!).release() } // Release the function definition
        )

        guard code == SQLITE_OK else {
            throw SQLiteError(statusCode: code, connection: connection)
        }
    }
    
    /// Invokes `sqlite3_create_function_v2()` to uninstall a custom function.
    /// See https://sqlite.org/c3ref/create_function.html
    func uninstall(in connection: SQLiteConnection) throws {
        let code = sqlite_nio_sqlite3_create_function_v2(
            connection.handle.raw,
            self.identity.name,
            self.identity.nArg,
            self.eTextRep,
            nil, nil, nil, nil, nil
        )

        guard code == SQLITE_OK else {
            throw SQLiteError(statusCode: code, connection: connection)
        }
    }

    /// The way to compute the result of a function.
    /// Feeds the `pApp` parameter of `sqlite3_create_function_v2()`.
    /// http://sqlite.org/capi3ref.html#sqlite3_create_function
    private class FunctionDefinition {
        let compute: (Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> (any SQLiteDataConvertible)?
        init(compute: @Sendable @escaping (Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> (any SQLiteDataConvertible)?) {
            self.compute = compute
        }
    }

    /// The way to start an aggregate.
    /// Feeds the `pApp` parameter of `sqlite3_create_function_v2()`.
    /// http://sqlite.org/capi3ref.html#sqlite3_create_function
    private class AggregateDefinition {
        let makeAggregate: () -> any SQLiteCustomAggregate
        init(makeAggregate: @Sendable @escaping () -> any SQLiteCustomAggregate) {
            self.makeAggregate = makeAggregate
        }
    }

    /// The current state of an aggregate, storable in SQLite.
    private final class AggregateContext {
        var aggregate: any SQLiteCustomAggregate
        var hasErrored = false
        init(aggregate: any SQLiteCustomAggregate) {
            self.aggregate = aggregate
        }
    }

    /// A function kind: an "SQL function" or an "aggregate".
    /// See http://sqlite.org/capi3ref.html#sqlite3_create_function
    private enum Kind {
        /// A regular function: `SELECT f(1)`
        case function(@Sendable (Int32, UnsafeMutablePointer<OpaquePointer?>?) throws -> (any SQLiteDataConvertible)?)

        /// An aggregate: `SELECT f(foo) FROM bar GROUP BY baz`
        case aggregate(@Sendable () -> any SQLiteCustomAggregate)

        /// Feeds the `pApp` parameter of `sqlite3_create_function_v2()`.
        /// http://sqlite.org/capi3ref.html#sqlite3_create_function
        var definition: AnyObject {
            switch self {
            case .function(let compute):
                return FunctionDefinition(compute: compute)
            case .aggregate(let makeAggregate):
                return AggregateDefinition(makeAggregate: makeAggregate)
            }
        }

        /// Feeds the `xFunc` parameter of `sqlite3_create_function_v2()`.
        /// http://sqlite.org/capi3ref.html#sqlite3_create_function
        var xFunc: (@convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void)? {
            guard case .function = self else { return nil }
            return { (sqliteContext, argc, argv) in
                let definition = Unmanaged<FunctionDefinition>
                    .fromOpaque(sqlite_nio_sqlite3_user_data(sqliteContext))
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

        /// Feeds the `xStep` parameter of `sqlite3_create_function_v2()`.
        /// http://sqlite.org/capi3ref.html#sqlite3_create_function
        var xStep: (@convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void)? {
            guard case .aggregate = self else { return nil }
            return { (sqliteContext, argc, argv) in
                let aggregateContextU = SQLiteCustomFunction.unmanagedAggregateContext(sqliteContext)
                let aggregateContext = aggregateContextU.takeUnretainedValue()
                assert(!aggregateContext.hasErrored) // assert SQLite behavior
                do {
                    let count = Int(argc)
                    let arguments = try (0 ..< count).map { index -> SQLiteData in
                        guard let value = argv?[index] else {
                            throw SQLiteCustomFunctionArgumentError(count: count, index: index)
                        }
                        return try SQLiteData(sqliteValue: value)
                    }
                    try aggregateContext.aggregate.step(arguments)
                } catch {
                    aggregateContext.hasErrored = true
                    SQLiteCustomFunction.report(error: error, in: sqliteContext)
                }
            }
        }

        /// Feeds the `xFinal` parameter of `sqlite3_create_function_v2()`.
        /// http://sqlite.org/capi3ref.html#sqlite3_create_function
        var xFinal: (@convention(c) (OpaquePointer?) -> Void)? {
            guard case .aggregate = self else { return nil }
            return { (sqliteContext) in
                let aggregateContext = SQLiteCustomFunction.unmanagedAggregateContext(sqliteContext).takeRetainedValue()

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
        let stride = MemoryLayout<OpaquePointer?>.stride
        let aggregateContextBufferP = UnsafeMutableRawBufferPointer(
            start: sqlite_nio_sqlite3_aggregate_context(sqliteContext, Int32(stride))!,
            count: stride)
        
        return aggregateContextBufferP.withMemoryRebound(to: OpaquePointer?.self) { aggregateContextBufferP -> Unmanaged<AggregateContext> in
            if let contextPtr = aggregateContextBufferP[0] {
                // Buffer contains non-null pointer; return existing context.
                return Unmanaged<AggregateContext>.fromOpaque(.init(contextPtr))
            } else {
                // Buffer contains null pointer; create new context.
                let definition = Unmanaged<AggregateDefinition>.fromOpaque(sqlite_nio_sqlite3_user_data(sqliteContext)).takeUnretainedValue()
                let context = Unmanaged.passRetained(AggregateContext(aggregate: definition.makeAggregate()))
                
                aggregateContextBufferP[0] = .some(.init(context.toOpaque()))
                return context
            }
        }
    }

    private static func report(result: (any SQLiteDataConvertible)?, in sqliteContext: OpaquePointer?) {
        switch result?.sqliteData ?? .null {
        case .null:
            sqlite_nio_sqlite3_result_null(sqliteContext)
        case .integer(let int64):
            sqlite_nio_sqlite3_result_int64(sqliteContext, Int64(int64))
        case .float(let double):
            sqlite_nio_sqlite3_result_double(sqliteContext, double)
        case .text(let string):
            sqlite_nio_sqlite3_result_text(sqliteContext, string, -1, SQLITE_TRANSIENT)
        case .blob(let value):
            value.withUnsafeReadableBytes { pointer in
                sqlite_nio_sqlite3_result_blob(sqliteContext, pointer.baseAddress, Int32(value.readableBytes), SQLITE_TRANSIENT)
            }
        }
    }

    private static func report(error: any Swift.Error, in sqliteContext: OpaquePointer?) {
        if let error = error as? SQLiteError {
            sqlite_nio_sqlite3_result_error(sqliteContext, error.message, -1)
            sqlite_nio_sqlite3_result_error_code(sqliteContext, error.reason.statusCode)
        } else {
            sqlite_nio_sqlite3_result_error(sqliteContext, "\(error)", -1)
        }
    }
}

extension SQLiteCustomFunction {
    // See `Hashable.hash(into:)`.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// Two functions are equal if they share the same name and arity.
    public static func == (lhs: SQLiteCustomFunction, rhs: SQLiteCustomFunction) -> Bool {
        lhs.identity == rhs.identity
    }
}

/// The protocol for custom SQLite aggregates.
///
/// For example:
///
///     struct MySum: DatabaseAggregate {
///         var sum: Int = 0
///
///         mutating func step(_ dbValues: [SQLiteData]) {
///             if let int = dbValues[0].integer {
///                 sum += int
///             }
///         }
///
///         func finalize() -> (any SQLiteDataConvertible)? {
///             sum
///         }
///     }
///
///     let connection: SQLiteConnection = ...
///     let fn = SQLiteCustomFunction("mysum", argumentCount: 1, aggregate: MySum.self)
///     try await connection.install(customFunction: fn).get()
///     try await connection.query("CREATE TABLE test(i)").get()
///     try await connection.query("INSERT INTO test(i) VALUES (1)").get()
///     try await connection.query("INSERT INTO test(i) VALUES (2)").get()
///     let sum = (try await connection.query("SELECT mysum(i) FROM test").get().first?.columns.first?.integer)!
public protocol SQLiteCustomAggregate {
    /// Create an aggregate.
    init()

    /// This method is called at each step of the aggregation.
    ///
    /// The dbValues argument contains as many values as given to the SQL
    /// aggregate function.
    ///
    ///     -- One value
    ///     SELECT maxLength(name) FROM player
    ///
    ///     -- Two values
    ///     SELECT maxFullNameLength(firstName, lastName) FROM player
    ///
    /// This method is never called after the ``finalize()`` method has been called.
    mutating func step(_ values: [SQLiteData]) throws

    /// Return the final result. Called only once, at the end of the aggregation.
    func finalize() throws -> (any SQLiteDataConvertible)?
}

extension SQLiteCustomFunction: Sendable {}
