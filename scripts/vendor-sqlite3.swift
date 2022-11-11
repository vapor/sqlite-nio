import Foundation
#if os(Linux)
import FoundationNetworking
#endif

let usage = """
SQLite3 library script

This script provides commands for working with the embedded C sqlite3 library.

Commands:

    bump-latest-version [--force]

        Fetches the latest sqlite version from https://sqlite.org/download.html
        and updates the CSQLite source, but only if the the latest version is a
        patch release. If --force is provided, the CSQLite source will be
        updated even if it is a major or minor release.

    print-system-sqlite-options

        Prints the compile options associated with the system installed sqlite
        version. The options are printed out pre-formatted for copy-paste into
        Package.swift as an array of [CSetting]. This command is useful for
        comparing and modifying platform specific compile options.

    update-version <year/version>

        Updates the CSQLite source to the specified version.
"""

// Constants
let sqliteURL = "https://sqlite.org"
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let cSQLiteDirectory = root
    .appendingPathComponent("Sources")
    .appendingPathComponent("CSQLite")
let versionFile = cSQLiteDirectory
    .appendingPathComponent("version.txt")
let sqlite3Source = cSQLiteDirectory
    .appendingPathComponent("sqlite3.c")
let sqlite3Header = cSQLiteDirectory
    .appendingPathComponent("include")
    .appendingPathComponent("sqlite3.h")

let unzip: URL!
let sqlite3: URL!
let sha3sum: URL!
do {
    unzip = try ensureExecutable("unzip")
    sqlite3 = try ensureExecutable("sqlite3")
    sha3sum = try ensureExecutable("sha3sum")
    try main()
} catch let error as String {
    print(error)
    exit(-1)
}

// MARK: Main

func main() throws {
    var args = CommandLine.arguments[...]
    _ = args.popFirst()
    guard !args.contains(where: { $0 == "-h" || $0 == "--help" }),
          let command = args.popFirst() else
    {
        throw usage
    }

    switch command {
        case "bump-latest-version": try bumpVersion(args)
        case "print-system-sqlite-options": try printSystemSQLiteCompileOptions(args)
        case "update-version": try updateVersion(args)
        default: throw usage
    }
}

// MARK: Commands

/// bump-latest-version
func bumpVersion(_ args: ArraySlice<String>) throws {
    let force = args.contains(where: { $0 == "-f" || $0 == "--force" })

    let currentVersion = Version(from: versionFile)
    let sqliteDownloadURL = URL(string: "\(sqliteURL)/download.html")!
    let data = try httpGet(from: sqliteDownloadURL)
    guard let content = String(data: data, encoding: .utf8) else {
        throw "Invalid data returned from \(sqliteDownloadURL)"
    }

    var amalgamationProduct: String?
    content.enumerateLines { (line, _) in
        guard line.hasPrefix("PRODUCT,"), line.contains("-amalgamation-") else {
            return
        }
        amalgamationProduct = line
    }

    guard let amalgamationProduct = amalgamationProduct else {
        throw "SQLite amalgamation product not found at \(sqliteDownloadURL)"
    }

    let product = try ProductInfo(from: amalgamationProduct)
    if !force, let currentVersion = currentVersion {
        guard product.version.major == currentVersion.major,
              product.version.minor == currentVersion.minor,
              product.version.patch > currentVersion.patch else {
            print("Not upgrading from \(currentVersion) to \(product.version)")
            return
        }
    }
    try downloadAndUnzipSQLite(
        from: product.downloadURL,
        to: product.filename,
        expectedSize: product.sizeInBytes,
        expectedSha3Sum: product.sha3Hash
    )
    try product.version.stamp(from: product.downloadURL)
    print("Upgraded from \(String(describing: currentVersion)) to \(product.version)")
}

/// print-system-sqlite-options
func printSystemSQLiteCompileOptions(_ args: ArraySlice<String>) throws {
    guard let compileOptions = try subprocess(sqlite3, [":memory:", "PRAGMA compile_options;"], captureStdout: true) else {
        throw "Unknown sqlite3 compile options"
    }
    guard let sqliteVersion = try subprocess(sqlite3, ["--version"], captureStdout: true) else {
        throw "Unknown sqlite3 version"
    }

    let optionsArray = compileOptions.split(separator: "\n")
    let compiler = optionsArray.first(where: { $0.hasPrefix("COMPILER=") })?.split(separator: "=").last
    let options = optionsArray.filter {
        !$0.hasPrefix("COMPILER") && !$0.hasPrefix("ENABLE_SQLLOG")
    }
    let parameterOptions = options
        .filter { $0.contains("=") }
        .map {
            let parts = $0.split(separator: "=")
            return #"    .define("SQLITE_\#(parts[0])", to: "\#(parts[1])"),"#
        }
        .joined(separator: "\n")
    let parameterLessOptions = options
        .filter { !$0.contains("=") }
        .map {
            return #"    .define("SQLITE_\#($0)"),"#
        }
        .joined(separator: "\n")
    print("// Derived from sqlite3 version \(sqliteVersion)")
    print("// compiled with \(compiler ?? "unknown")")
    print("let cSQLiteSettings: [CSetting] = [")
    print(parameterOptions)
    print(parameterLessOptions)
    print("]")
}

/// update-version
func updateVersion(_ args: ArraySlice<String>) throws {
    var args = args
    let yearVersion = args.popFirst()
    guard let yearAndVersion = yearVersion?.split(separator: "/"),
          yearAndVersion.count == 2,
          let year = Int(yearAndVersion[0]),
          let version = Version(from: String(yearAndVersion[1])) else {
        throw "Invalid year and version: \(String(describing: yearVersion))"
    }

    let currentVersion = Version(from: versionFile)
    let filename = "sqlite-amalgamation-\(version.asDownloadVersion).zip"
    let sqliteDownloadURL = URL(string: "\(sqliteURL)/\(year)/\(filename)")!
    try downloadAndUnzipSQLite(from: sqliteDownloadURL, to: filename, expectedSize: nil, expectedSha3Sum: nil)
    try version.stamp(from: sqliteDownloadURL)
    print("Upgraded from \(String(describing: currentVersion)) to \(version)")
}

// MARK: Utilities

public struct Version: CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let branch: Int

    init?(from string: String) {
        let version = string.split(separator: ".")
        guard version.count >= 3,
              let major = Int(version[0]),
              let minor = Int(version[1]),
              let patch = Int(version[2]) else
        {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        if version.count == 4 {
            guard let branch = Int(version[3]) else {
                return nil
            }
            self.branch = branch
        } else {
            self.branch = 0
        }
    }

    init?(from versionFile: URL) {
        var versionString: String?
        try? String(contentsOfFile: versionFile.path).trimmingCharacters(in: .whitespacesAndNewlines).enumerateLines { (line, _) in
            guard !line.hasPrefix("//") else {
                return
            }
            versionString = line
        }
        self.init(from: versionString ?? "")
    }

    func stamp(from downloadURL: URL) throws {
        try """
        // This directory is derived from SQLite downloaded from \(downloadURL)
        \(self.description)
        """.write(to: versionFile, atomically: true, encoding: .utf8)
    }

    public var description: String {
        [major, minor, patch, branch].map(String.init).joined(separator: ".")
    }

    var asDownloadVersion: String {
        let major = String(major)
        let minor = String(format: "%02d", minor)
        let patch = String(format: "%02d", patch)
        let branch = String(format: "%02d", branch)
        return [major, minor, patch, branch].joined(separator: "")
    }
}

extension Optional: CustomStringConvertible where Wrapped == Version {
    public var description: String {
        switch self {
            case .none: return "unknown"
            case let .some(version): return version.description
        }
    }
}

struct ProductInfo {
    let version: Version
    let downloadURL: URL
    let filename: String
    let sizeInBytes: Int
    let sha3Hash: String

    init(from csvRow: String) throws {
        let columns = csvRow.split(separator: ",")
        guard columns.count == 5 else {
            throw "Invalid product info, expecting 5 columns in \(csvRow)"
        }
        guard let version = Version(from: String(columns[1])) else {
            throw "Invalid product version \(columns[1])"
        }
        let relativeURL = columns[2]
        guard let downloadURL = URL(string: "\(sqliteURL)/\(relativeURL)"),
              let filename = relativeURL.split(separator: "/").last else {
            throw "Invalid product relative URL \(relativeURL)"
        }
        guard let sizeInBytes = Int(columns[3]) else {
            throw "Invalid product archive size \(columns[3])"
        }

        self.version = version
        self.downloadURL = downloadURL
        self.filename = String(filename)
        self.sizeInBytes = sizeInBytes
        self.sha3Hash = String(columns[4])
    }
}

func httpGet(from url: URL) throws -> Data {
    let group = DispatchGroup()
    group.enter()
    var getError: Error?
    var getData: Data?
    URLSession.shared.dataTask(with: url) { data, response, error in
        defer { group.leave() }
        if let error = error {
            getError = error
            return
        }
        guard let data = data else {
            getError = "No data returned from \(url)"
            return
        }
        getData = data
    }.resume()
    group.wait()
    if let getError = getError {
        throw getError
    }
    return getData!
}

func downloadAndUnzipSQLite(from url: URL, to filename: String, expectedSize: Int?, expectedSha3Sum: String?) throws {
    let productData = try httpGet(from: url)
    if let expectedSize = expectedSize {
        guard productData.count == expectedSize else {
            throw "Downloaded SQLite archive size \(productData.count) does not match expected \(expectedSize)"
        }
    }
    let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(filename)
    let directory = file.deletingPathExtension()
    try productData.write(to: file)
    if let expectedSha3Sum = expectedSha3Sum {
        let sha3Output = try subprocess(sha3sum, ["-z", "-a", "256", file.path], captureStdout: true)
        guard let sha3AndFile = sha3Output?.split(separator: " "),
              sha3AndFile.count == 2 else {
            throw "Unknown sha3 sum: \(String(describing: sha3Output))"
        }
        guard expectedSha3Sum == sha3AndFile[0] else {
            throw "Unexpected sha3: \(expectedSha3Sum) != \(sha3AndFile[0])"
        }
    }
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: directory)
    }

    try subprocess(unzip, [file.path], captureStdout: false)

    _ = try FileManager.default.replaceItemAt(sqlite3Source, withItemAt: directory.appendingPathComponent("sqlite3.c"))
    _ = try FileManager.default.replaceItemAt(sqlite3Header, withItemAt: directory.appendingPathComponent("sqlite3.h"))
}

@discardableResult
func subprocess(_ executable: URL, _ arguments: [String], captureStdout: Bool) throws -> String? {
    guard FileManager.default.fileExists(atPath: executable.path) else {
        throw "This script requires \(executable.path), please install it and try again"
    }

    let stdout = Pipe()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if captureStdout {
        process.standardOutput = stdout
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw "\(executable.path) failed: \(process.terminationStatus)"
    }
    if captureStdout {
        return String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        return nil
    }
}

func ensureExecutable(_ executable: String) throws -> URL {
    let bash = URL(fileURLWithPath: "/bin/bash")
    guard let executablePath = try? subprocess(bash, ["-c", "which \(executable)"], captureStdout: true) else {
        throw "This script requires \(executable), verify your $PATH or install the executable and try again"
    }
    return URL(fileURLWithPath: executablePath)
}

extension String: Error {}
