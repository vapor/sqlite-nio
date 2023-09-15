#if canImport(Darwin)

import Foundation

extension Foundation.Process {
    static func run(_ command: String, _ arguments: String...) throws { try Self.run(command, arguments) }
    static func run(_ command: String, _ arguments: [String]) throws {
        guard command.starts(with: "/") else { return try Self.run("/usr/bin/env", [command] + arguments) }
        let process = try Self.run(URL(fileURLWithPath: command, isDirectory: false), arguments: arguments)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VendoringError("'\(command) \(arguments.joined(separator: " "))' exited with status \(process.terminationStatus)")
        }
    }
    
    static func popen(_ command: String, _ arguments: String...) async throws -> String { try await Self.popen(command, arguments) }
    static func popen(_ command: String, _ arguments: [String]) async throws -> String {
        guard command.starts(with: "/") else { return try await Self.popen("/usr/bin/env", [command] + arguments) }

        var output: [UInt8] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command, isDirectory: false)
        process.arguments = arguments
        process.standardOutput = Pipe()
        try process.run()
        for try await byte in (process.standardOutput as! Pipe).fileHandleForReading.bytes { output.append(byte) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VendoringError("'\(command) \(arguments.joined(separator: " "))' exited with status \(process.terminationStatus)")
        }
        return String(decoding: output, as: UTF8.self)
    }
}

#endif
