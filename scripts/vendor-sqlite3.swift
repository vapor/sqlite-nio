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
let vendorPrefix = "sqlite_nio"
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let cSQLiteDirectory = root
    .appendingPathComponent("Sources")
    .appendingPathComponent("CSQLite")
let cSQLiteIncludeDirectory = cSQLiteDirectory
    .appendingPathComponent("include")
let versionFile = cSQLiteDirectory
    .appendingPathComponent("version.txt")
let sqlite3Source = cSQLiteDirectory
    .appendingPathComponent("sqlite3.c")
let sqlite3Header = cSQLiteIncludeDirectory
    .appendingPathComponent("sqlite3.h")
let vendorHeader = cSQLiteIncludeDirectory
    .appendingPathComponent("sqlite3_vendor.h")
let packageFile = root
    .appendingPathComponent("Package.swift")

let unzip: URL!
let sqlite3: URL!
let sha3sum: URL!
let swift: URL!
let ar: URL!
let nm: URL!
do {
    unzip = try await ensureExecutable("unzip")
    sqlite3 = try await ensureExecutable("sqlite3")
    sha3sum = try await ensureExecutable("sha3sum")
    swift = try await ensureExecutable("swift")
    ar = try await ensureExecutable("ar")
    nm = try await ensureExecutable("nm")

    try await main()
} catch let error as String {
    print(error)
    exit(-1)
}

// MARK: Main

func main() async throws {
    var args = CommandLine.arguments[...]
    _ = args.popFirst()
    guard !args.contains(where: { $0 == "-h" || $0 == "--help" }),
          let command = args.popFirst() else
    {
        throw usage
    }

    switch command {
        case "bump-latest-version": try await bumpVersion(args)
        case "print-system-sqlite-options": try await printSystemSQLiteCompileOptions(args)
        case "update-version": try await updateVersion(args)
        default: throw usage
    }
}

// MARK: Commands

/// bump-latest-version
func bumpVersion(_ args: ArraySlice<String>) async throws {
    let force = args.contains(where: { $0 == "-f" || $0 == "--force" })

    let currentVersion = Version(from: versionFile)
    let sqliteDownloadURL = URL(string: "\(sqliteURL)/download.html")!
    let (data, _) = try await URLSession.shared.data(from: sqliteDownloadURL)
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
    try await downloadAndUnzipSQLite(
        from: product.downloadURL,
        to: product.filename,
        expectedSize: product.sizeInBytes,
        expectedSha3Sum: product.sha3Hash
    )
    try await addVendorPrefixToSQLite()
    try product.version.stamp(from: product.downloadURL)
    print("Upgraded from \(String(describing: currentVersion)) to \(product.version)")
}

/// print-system-sqlite-options
func printSystemSQLiteCompileOptions(_ args: ArraySlice<String>) async throws {
    guard let compileOptions = try await subprocess(sqlite3, [":memory:", "PRAGMA compile_options;"], captureStdout: true) else {
        throw "Unknown sqlite3 compile options"
    }
    guard let sqliteVersion = try await subprocess(sqlite3, ["--version"], captureStdout: true) else {
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
func updateVersion(_ args: ArraySlice<String>) async throws {
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
    try await downloadAndUnzipSQLite(from: sqliteDownloadURL, to: filename, expectedSize: nil, expectedSha3Sum: nil)
    try await addVendorPrefixToSQLite()
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

func downloadAndUnzipSQLite(from url: URL, to filename: String, expectedSize: Int?, expectedSha3Sum: String?) async throws {
    let (productData, _) = try await URLSession.shared.data(from: url)
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
        let sha3Output = try await subprocess(sha3sum, ["-z", "-a", "256", file.path], captureStdout: true)
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

    try await subprocess(unzip, [file.path], captureStdout: false)

    _ = try FileManager.default.replaceItemAt(sqlite3Source, withItemAt: directory.appendingPathComponent("sqlite3.c"))
    _ = try FileManager.default.replaceItemAt(sqlite3Header, withItemAt: directory.appendingPathComponent("sqlite3.h"))
}

/// Adds our vendor prefix to both sqlite.c and sqlite.h to avoid potential namespace collisions with other versions of sqlite.
func addVendorPrefixToSQLite() async throws {
    let symbols = try await getSymbolsToPrefix()
    print("Prefixing symbols in \(sqlite3Header.lastPathComponent) with \"\(vendorPrefix)\"...")
    try await addPrefix(vendorPrefix, to: symbols, in: sqlite3Header)
    print("Prefixing symbols in \(sqlite3Source.lastPathComponent) with \"\(vendorPrefix)\"...")
    try await addPrefix(vendorPrefix, to: symbols, in: sqlite3Source)
}

/// Add the given prefix to every string in symbols in the given file.
func addPrefix(_ prefix: String, to symbols: [String], in url: URL) async throws {
    // Use streaming reads so we don't load the entire file into memory
    guard let readHandle = FileHandle(forReadingAtPath: url.path) else {
        throw "Cannot open \(url.path) for reading"
    }
    defer { readHandle.closeFile() }

    // Write modifications to a temporary file
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
    FileManager.default.createFile(atPath: tempFile.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    guard let writeHandle = FileHandle(forWritingAtPath: tempFile.path) else {
        throw "Cannot open \(tempFile) for writing"
    }
    defer { writeHandle.closeFile() }

    for try await line in readHandle.bytes.lines {
        var newLine = line
        for symbol in symbols {
            newLine = newLine.replacingOccurrences(of: symbol, with: "\(prefix)_\(symbol)", options: .literal)
        }
        writeHandle.write(Data(newLine.utf8))
        writeHandle.write(Data("\n".utf8))
    }

    _ = try FileManager.default.replaceItemAt(url, withItemAt: tempFile)
}

/// Get the list of external symbols that we need to add our vendor prefix to. Uses ar and nm and does some
/// sorting and filter on the symbol list to make prefixing easier later.
func getSymbolsToPrefix() async throws -> [String] {
    // Make the CSQLite static library target available for easily getting the list of symbols
    let package = try String(contentsOfFile: packageFile.path)
    try package
        .split(separator: "\n")
        .filter { !$0.contains("/* VENDOR_START") && !$0.contains("VENDOR_END */") }
        .joined(separator: "\n")
        .write(to: packageFile, atomically: true, encoding: .utf8)
    defer { try? package.write(to: packageFile, atomically: true, encoding: .utf8) }

    try await subprocess(swift, ["build", "--product", "CSQLite"], captureStdout: false)
    guard let binPath = try await subprocess(swift, ["build", "--show-bin-path"], captureStdout: true) else {
        throw "Cannot determine swift bin path"
    }
    let buildDirectory = URL(fileURLWithPath: binPath)
    let library = buildDirectory.appendingPathComponent("libCSQLite.a")

    // Inspect the resulting library for object files
    guard let objectFilenames = try await subprocess(ar, ["-t", library.path], captureStdout: true) else {
        throw "Cannot determine object files from \(library.path)"
    }
    let objectFiles = objectFilenames
        .split(separator: "\n")
        .filter { $0.hasSuffix(".o") }
        .map {
            buildDirectory
                .appendingPathComponent("CSQLite.build")
                .appendingPathComponent(String($0))
        }

    // Get all external symbols
    var symbolsToRewrite = Set<String>()
    for objectFile in objectFiles {
        guard let symbols = try await subprocess(nm, ["-gUP", objectFile.path], captureStdout: true) else {
            continue
        }
        symbols.enumerateLines { (line, _) in
            let components = line.split(separator: " ")
            guard components.count == 4 else {
                return
            }
            // We only care about the name since we filtered using nm itself
            var symbol = components[0]
            _ = symbol.removeFirst() // Remove leading underscore prefix, e.g. _sqlite3_version
            symbolsToRewrite.insert(String(symbol))
        }
    }

    // Sort symbols by length so we can easily filter common prefixes
    let sortedSymbolsToRewrite = symbolsToRewrite.sorted(by: { $0.count < $1.count })

    // Exclude any symbols that have a common prefix with a shorter symbol
    // This allows us to:
    // - Avoid adding the prefix multiple times (e.g. sqlite3_open -> sqlite_nio_sqite_nio_sqlite3_open)
    // - Replace all symbols in a multi-symbol line since we guarantee each prefix only appears once
    var exclude = Set<String>()
    for (idx, symbol) in sortedSymbolsToRewrite.enumerated() {
        if exclude.contains(symbol) {
            continue
        }

        let next = sortedSymbolsToRewrite.index(after: idx)
        for symbol2 in sortedSymbolsToRewrite[next...] {
            if exclude.contains(symbol) {
                continue
            }
            if symbol2.hasPrefix(symbol) {
                exclude.insert(symbol2)
            }
        }
    }

    return sortedSymbolsToRewrite.filter { !exclude.contains($0) }
}

@discardableResult
func subprocess(_ executable: URL, _ arguments: [String], captureStdout: Bool) async throws -> String? {
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
        var output = ""
        for try await line in stdout.fileHandleForReading.bytes.characters {
            output += String(line)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        return nil
    }
}

func ensureExecutable(_ executable: String) async throws -> URL {
    let env = URL(fileURLWithPath: "/usr/bin/env")
    guard let executablePath = try? await subprocess(env, ["which", executable], captureStdout: true) else {
        throw "This script requires \(executable), verify your $PATH or install the executable and try again"
    }
    return URL(fileURLWithPath: executablePath)
}

extension String: Error {}
