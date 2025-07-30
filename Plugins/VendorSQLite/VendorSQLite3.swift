import Foundation
import PackagePlugin

#if canImport(Darwin)
@main
struct VendorSQLite: CommandPlugin {
    // Constants
    static let usage = """
        SQLite3/SQLCipher vendoring command

        This command provides support for updating the embedded C sqlite3 and/or SQLCipher libraries.

        Options:
          -h, --help              Show this help.
          -v, --verbose           Output detailed progress information.
          --force                 Run the vendoring process even if the currently embedded version
                                    is already up to date.
          --sqlite-only           Only update SQLite3 (default: update both).
          --sqlcipher-only        Only update SQLCipher (default: update both).
        """
    static let sqliteURL = URL(string: "https://sqlite.org")!
    static let githubURL = URL(string: "https://api.github.com/repos/sqlcipher/sqlcipher")!
    static let vendorPrefix = "sqlite_nio"
    
    nonisolated(unsafe) static var verbose = false
    
    var verbose: Bool { Self.verbose }
    
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = UsefulArgumentExtractor(arguments)
        
        // Handle arguments
        if extractor.extractFlag(named: "help", shortForm: "h") > 0 {
            return print(Self.usage)
        }
        
        let force = extractor.extractFlag(named: "force") > 0
        let sqliteOnly = extractor.extractFlag(named: "sqlite-only") > 0
        let sqlcipherOnly = extractor.extractFlag(named: "sqlcipher-only") > 0
        Self.verbose = extractor.extractFlag(named: "verbose", shortForm: "v") > 0

        guard extractor.remainingArguments.isEmpty else {
            for f in extractor.unextractedOptionsOrFlags { Diagnostics.error("Unknown option '\(f)'.") }
            if extractor.remainingArguments.count > extractor.unextractedOptionsOrFlags.count {
                Diagnostics.error("This command does not accept any arguments.")
            }
            return print(Self.usage)
        }
        
        // Validate conflicting options
        if sqliteOnly && sqlcipherOnly {
            Diagnostics.error("Cannot specify both --sqlite-only and --sqlcipher-only.")
            return print(Self.usage)
        }
        
        // Determine what to update
        let updateSQLite = !sqlcipherOnly
        let updateSQLCipher = !sqliteOnly
        
        // Clear work directory
        for item in try FileManager.default.contentsOfDirectory(at: context.pluginWorkDirectory.directoryUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) {
            try FileManager.default.removeItem(at: item)
        }
        
        // Update SQLite3 if requested
        if updateSQLite {
            try await vendorSQLite3(context: context, force: force)
        }
        
        // Update SQLCipher if requested  
        if updateSQLCipher {
            try await vendorSQLCipher(context: context, force: force)
        }
    }
    
    // MARK: - SQLite3 Vendoring
    
    private func vendorSQLite3(context: PluginContext, force: Bool) async throws {
        if self.verbose { Diagnostics.progress("=== Starting SQLite3 vendoring ===") }
        
        // Find C target
        guard let target = try context.package.targets(named: ["CSQLite"]).first.flatMap({ $0 as? ClangSourceModuleTarget }) else {
            throw VendoringError("Unable to find the CSQLite target in package.")
        }
        if self.verbose { Diagnostics.progress("Found CSQLite target with path \(target.directory)") }

        // Load current version
        guard let line = try await target.directory.appending("version.txt").fileUrl.lines.first(where: { !$0.starts(with: "//") }),
              let currentVersion = SemanticVersion(line)
        else {
            throw VendoringError("Could not read SQLite3 version stamp.")
        }
        if self.verbose { Diagnostics.progress("Current SQLite3 version: \(currentVersion)") }
        
        // Check for new versions
        let latestData = try await self.getSQLite3LatestDownloadInfo()
        
        guard latestData.version.major == currentVersion.major else {
            throw VendoringError("Latest SQLite3 version \(latestData.version) is not same major version as current \(currentVersion)")
        }
        guard force || latestData.version > currentVersion else {
            if self.verbose { Diagnostics.progress("SQLite3 version \(latestData.version) is not newer than current \(currentVersion), skipping") }
            return
        }
        if self.verbose { Diagnostics.progress("Found valid SQLite3 update: \(latestData.version)") }
        
        // Retrieve new sources, unzip, apply patches, replace current sources.
        try await self.downloadUnpackPatchSQLite3(latestData, context: context, target: target)
        
        // Extract symbol graph from new sources.
        let symbols = try await self.extractSymbols(for: target, context: context)

        // Prefix the symbols in the new sources.
        try await self.prefixFile(
            at: target.publicHeadersDirectory!.appending("\(Self.vendorPrefix)_sqlite3.h"),
            using: symbols,
            in: context
        )
        try await self.prefixFile(
            at: target.directory.appending("\(Self.vendorPrefix)_sqlite3.c"),
            using: symbols,
            in: context
        )
        
        // Stamp sources with updated version info.
        try """
        // This directory is generated from SQLite sources downloaded from \(latestData.downloadURL.absoluteString)
        \(latestData.version)
        
        """.write(to: target.directory.appending("version.txt").fileUrl, atomically: true, encoding: .utf8)

        Diagnostics.progress("SQLite3 upgraded from \(currentVersion) to \(latestData.version)")
    }
    
    private func getSQLite3LatestDownloadInfo() async throws -> Sqlite3ProductInfo {
        let downloadHtmlURL = Self.sqliteURL.appendingPathComponent("download.html", isDirectory: false)
        var foundCSV = false
        
        do {
            for try await line in downloadHtmlURL.lines {
                if !foundCSV, line.hasSuffix("Download product data for scripts to read") {
                    foundCSV = true
                } else if foundCSV, !line.hasPrefix("PRODUCT,") {
                    break
                } else if foundCSV, line.contains("sqlite-amalgamation") {
                    let info = try Sqlite3ProductInfo(from: line)
                    
                    if info.filename.starts(with: "sqlite-amalgamation") {
                        return info
                    }
                }
            }
        } catch let error as URLError where error.code == .cannotFindHost {
            throw VendoringError("DNS error when trying to load SQLite3 downloads list. You probably need to use --disable-sandbox. Underlying error: \(error)")
        }
        
        if foundCSV {
            throw VendoringError("Could not find latest SQLite3 version on download page.")
        } else {
            throw VendoringError("Failed to find product CSV table on SQLite3 download page.")
        }
    }
    
    private func downloadUnpackPatchSQLite3(
        _ latestData: Sqlite3ProductInfo,
        context: PluginContext,
        target: ClangSourceModuleTarget
    ) async throws {
        let zipPath = context.pluginWorkDirectory.appending(latestData.filename)

        if self.verbose { Diagnostics.progress("Starting SQLite3 download from \(latestData.downloadURL.absoluteString)") }
        try Process.run("curl", "-f\(self.verbose ? "" : "sS")Lo", "\(zipPath)", latestData.downloadURL.absoluteString)

        let zipSize = try zipPath.fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard zipSize == latestData.sizeInBytes else {
            throw VendoringError("SQLite3 download \(zipPath) wrong size (expected \(latestData.sizeInBytes), got \(zipSize ?? -1))")
        }

        let sha3Hash = try await Process.popen("sha3sum", "-a", "256", "\(zipPath)").prefix(while: { !$0.isWhitespace })
        guard sha3Hash == latestData.sha3Hash else {
            throw VendoringError("SQLite3 download \(zipPath) has wrong hash (expected \(latestData.sha3Hash), got \(sha3Hash))")
        }

        try Process.run("unzip", "-\(self.verbose ? "" : "q")j", "-d", "\(context.pluginWorkDirectory)", "\(zipPath)")
        try Process.run("patch", "-\(self.verbose ? "" : "s")d", "\(context.pluginWorkDirectory)", "-p1", "-u", "-i", "\(Path(#filePath).replacingLastComponent(with: "001-warnings-and-data-race.patch"))"
        )

        try FileManager.default.replaceItem(
            at: target.publicHeadersDirectory!.appending("\(Self.vendorPrefix)_sqlite3.h").fileUrl,
            withItemAt: context.pluginWorkDirectory.appending("sqlite3.h").fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
        try FileManager.default.replaceItem(
            at: target.directory.appending("\(Self.vendorPrefix)_sqlite3.c").fileUrl,
            withItemAt: context.pluginWorkDirectory.appending("sqlite3.c").fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
    }
    
    // MARK: - SQLCipher Vendoring
    
    private func vendorSQLCipher(context: PluginContext, force: Bool) async throws {
        if self.verbose { Diagnostics.progress("=== Starting SQLCipher vendoring ===") }
        
        // Find C target
        guard let target = try context.package.targets(named: ["CSQLCipher"]).first.flatMap({ $0 as? ClangSourceModuleTarget }) else {
            throw VendoringError("Unable to find the CSQLCipher target in package.")
        }
        if self.verbose { Diagnostics.progress("Found CSQLCipher target with path \(target.directory)") }

        // Load current version
        let versionFile = target.directory.appending("sqlcipher_version.txt")
        var currentVersion: SemanticVersion?
        
        if FileManager.default.fileExists(atPath: versionFile.string) {
            if let line = try await versionFile.fileUrl.lines.first(where: { !$0.starts(with: "//") }),
               let version = SemanticVersion(line) {
                currentVersion = version
            }
        }
        
        if let current = currentVersion {
            if self.verbose { Diagnostics.progress("Current SQLCipher version: \(current)") }
        } else {
            if self.verbose { Diagnostics.progress("No current SQLCipher version found") }
        }
        
        // Check for new versions from GitHub
        let latestData = try await self.getSQLCipherLatestDownloadInfo()
        
        if let current = currentVersion {
            guard latestData.version.major == current.major else {
                throw VendoringError("Latest SQLCipher version \(latestData.version) is not same major version as current \(current)")
            }
            guard force || latestData.version > current else {
                if self.verbose { Diagnostics.progress("SQLCipher version \(latestData.version) is not newer than current \(current), skipping") }
                return
            }
        }
        
        if self.verbose { Diagnostics.progress("Found valid SQLCipher update: \(latestData.version)") }
        
        // Download, build, and install SQLCipher
        try await self.downloadBuildInstallSQLCipher(latestData, context: context, target: target)
        
        // Extract symbol graph from new sources
        let symbols = try await self.extractSymbols(for: target, context: context)

        // Prefix the symbols in the new sources
        try await self.prefixSQLCipherFile(
            at: target.publicHeadersDirectory!.appending("\(Self.vendorPrefix)_sqlcipher.h"),
            using: symbols,
            in: context
        )
        try await self.prefixSQLCipherFile(
            at: target.directory.appending("\(Self.vendorPrefix)_sqlcipher.c"),
            using: symbols,
            in: context
        )
        
        // Stamp sources with updated version info.
        try """
        // This directory contains SQLCipher sources downloaded from \(latestData.downloadURL.absoluteString)
        \(latestData.version)
        
        """.write(to: versionFile.fileUrl, atomically: true, encoding: .utf8)

        let message = currentVersion.map { "SQLCipher upgraded from \($0) to \(latestData.version)" } ?? "SQLCipher installed \(latestData.version)"
        Diagnostics.progress(message)
    }
    
    private func getSQLCipherLatestDownloadInfo() async throws -> SqlcipherProductInfo {
        let releasesURL = Self.githubURL.appendingPathComponent("releases/latest")
        
        do {
            let releaseData = try Data(contentsOf: releasesURL)
            let json = try JSONSerialization.jsonObject(with: releaseData) as? [String: Any]
            
            guard let tagName = json?["tag_name"] as? String,
                  let tarballURL = json?["tarball_url"] as? String else {
                throw VendoringError("Could not parse latest SQLCipher release information from GitHub API")
            }
            
            return try SqlcipherProductInfo(tagName: tagName, tarballURL: tarballURL)
            
        } catch let error as URLError where error.code == .cannotFindHost {
            throw VendoringError("DNS error when trying to load SQLCipher releases list. You probably need to use --disable-sandbox. Underlying error: \(error)")
        }
    }
    
    private func downloadBuildInstallSQLCipher(
        _ latestData: SqlcipherProductInfo,
        context: PluginContext,
        target: ClangSourceModuleTarget
    ) async throws {
        let tarPath = context.pluginWorkDirectory.appending("\(latestData.tagName).tar.gz")
        let extractDir = context.pluginWorkDirectory.appending("sqlcipher-extract")

        // Download
        if self.verbose { Diagnostics.progress("Starting SQLCipher download from \(latestData.downloadURL.absoluteString)") }
        try Process.run("curl", "-f\(self.verbose ? "" : "sS")Lo", "\(tarPath)", latestData.downloadURL.absoluteString)

        // Extract
        if self.verbose { Diagnostics.progress("Extracting SQLCipher source") }
        try FileManager.default.createDirectory(at: extractDir.directoryUrl, withIntermediateDirectories: true)
        try Process.run("tar", "-xzf", "\(tarPath)", "-C", "\(extractDir)", "--strip-components=1")

        // Build amalgamation
        if self.verbose { Diagnostics.progress("Building SQLCipher amalgamation") }
        
        // Check for OpenSSL (try common locations)
        let possibleOpensslPaths = [
            "/opt/homebrew/opt/openssl@3",
            "/usr/local/opt/openssl@3", 
            "/opt/homebrew/opt/openssl",
            "/usr/local/opt/openssl"
        ]
        
        var opensslPath: String?
        for path in possibleOpensslPaths {
            if FileManager.default.fileExists(atPath: path) {
                opensslPath = path
                break
            }
        }
        
        guard let ssl = opensslPath else {
            throw VendoringError("OpenSSL not found. Please install it via 'brew install openssl@3'")
        }
        
        if self.verbose { Diagnostics.progress("Using OpenSSL at: \(ssl)") }
        
        // Create build directory
        let buildDir = extractDir.appending("build")
        try FileManager.default.createDirectory(at: buildDir.directoryUrl, withIntermediateDirectories: true)
        
        // Configure SQLCipher with encryption support (from build directory)
        let configCommand = "cd \(buildDir) && ../configure --with-tempstore=yes --disable-tcl CFLAGS=\"-DSQLITE_HAS_CODEC -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -I\(ssl)/include\" LDFLAGS=\"-L\(ssl)/lib -lcrypto\""
        try Process.run("sh", "-c", configCommand)
        
        // Build amalgamation
        try Process.run("sh", "-c", "cd \(buildDir) && make")
        
        // Verify build products exist in build directory
        let amalgamationC = buildDir.appending("sqlite3.c")
        let amalgamationH = buildDir.appending("sqlite3.h")
        
        guard FileManager.default.fileExists(atPath: amalgamationC.string),
              FileManager.default.fileExists(atPath: amalgamationH.string) else {
            throw VendoringError("SQLCipher build failed - amalgamation files not created")
        }
        
        if self.verbose { 
            let cSize = try amalgamationC.fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let hSize = try amalgamationH.fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            Diagnostics.progress("Built SQLCipher amalgamation - sqlite3.c: \(cSize) bytes, sqlite3.h: \(hSize) bytes")
        }
        
        // Replace files with prefixed names for SQLCipher
        try FileManager.default.replaceItem(
            at: target.publicHeadersDirectory!.appending("\(Self.vendorPrefix)_sqlcipher.h").fileUrl,
            withItemAt: amalgamationH.fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
        try FileManager.default.replaceItem(
            at: target.directory.appending("\(Self.vendorPrefix)_sqlcipher.c").fileUrl,
            withItemAt: amalgamationC.fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
        
        if self.verbose { Diagnostics.progress("Installed SQLCipher files to CSQLCipher target") }
    }

    // MARK: - Symbol Processing
    
    private func extractSymbols(for target: any PackagePlugin.SourceModuleTarget, context: PluginContext) async throws -> [Substring] {
        // Get a list of relevant symbols from the SPM symbol graph.
        if self.verbose { Diagnostics.progress("Starting symbol graph generation for \(target.name)") }
        let symbolGraphFile = try self.packageManager.getSymbolGraph(for: target, options: .init(
            minimumAccessLevel: .public, includeSynthesized: false, includeSPI: false, emitExtensionBlocks: false
        )).directoryPath.appending("\(target.name).symbols.json")
        
        let symbolGraph = try JSONDecoder().decode(SymbolGraph.self, from: Data(contentsOf: symbolGraphFile.fileUrl))
        
        let graphSymbols = Set(symbolGraph.symbols.compactMap {
            ($0.kind.identifier == "swift.func" ? $0.identifier.precise.dropFirst("c:@F@".count) :
            ($0.kind.identifier == "swift.var" && !$0.identifier.precise.contains("@macro@") ?
                $0.identifier.precise.dropFirst("c:@".count) :
            nil))
        })
        if self.verbose { Diagnostics.progress("Found \(graphSymbols.count) symbols in the graph") }
        
        // The symbol graph can only handle symbols that ClangImporter is able to import into Swift, which excludes
        // functions that use C variadic args like sqlite3_config(), so use nm to extract a symbol list from the
        // generated object file(s) as well.
        if self.verbose { Diagnostics.progress("Starting object file generation") }
        guard try self.packageManager.build(.target(target.name), parameters: .init()).succeeded else {
            throw VendoringError("Build command failed (unspecified reason)")
        }

        let objDir = context.package.directory.appending(".build", "debug", "\(target.name).build")
        var objSymbols: Set<Substring> = []
        for object in try FileManager.default.contentsOfDirectory(at: objDir.directoryUrl, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "o" })
        {
            objSymbols.formUnion(try await Process.popen("nm", "-gUj", object.path).split(separator: "\n").map { $0.dropFirst() })
        }
        if self.verbose { Diagnostics.progress("Got \(objSymbols.count) symbols from object files")}
        
        // It turns out that both the symbol graph and the object files have symbols that the other doesn't, so we
        // take the union of both.
        let allSymbols = graphSymbols.union(objSymbols).sorted()
        if self.verbose { Diagnostics.progress("Loaded \(allSymbols.count) unique symbols from the graph and objects") }
        
        // Remove symbols that have a common prefix matching entire shorter symbol names. This both prevents multiple
        // prefixing of symbols and cuts down on the number of replacements we do per input line.
        let commonPrefixSymbols = allSymbols.reduce(into: [Substring]()) { res, sym in
            if res.last.map({ !sym.starts(with: $0) }) ?? true { res.append(sym) }
        }
        if self.verbose { Diagnostics.progress("\(allSymbols.count - commonPrefixSymbols.count) symbols had common prefixes") }
        
        return commonPrefixSymbols
    }
    
    private func prefixFile(at file: Path, using symbols: [Substring], in context: PluginContext) async throws {
        do { // Make sure the file handles are closed before we move the output into place.
            let reader = try FileHandle(forReadingFrom: file.fileUrl)
            defer { try? reader.close() }
            
            let outputFile = context.pluginWorkDirectory.appending(file.lastComponent)
            // `FileHandle(forWritingTo:)` refuses to create new files.
            FileManager.default.createFile(atPath: outputFile.string, contents: nil)
            let writer = try FileHandle(forWritingTo: outputFile.fileUrl)
            defer { try? writer.close() }
            
            let minimalCommonPrefix = symbols.reduce(symbols[0]) { $1.commonPrefix(with: $0, options: .literal)[...] }
            
            if self.verbose { Diagnostics.progress("Prefixing symbols in \(file.lastComponent) (minimum prefix \(minimalCommonPrefix))") }
            for try await line in reader.bytes.keepingEmptySubsequencesLines {
                let oline = line.contains(minimalCommonPrefix) ?
                    symbols.reduce(line, { $0.replacingOccurrences(of: $1, with: "\(Self.vendorPrefix)_\($1)") }) :
                    line
                
                try writer.write(contentsOf: Array("\(oline)\n".utf8))
            }
        }
        
        try FileManager.default.replaceItem(
            at: file.fileUrl,
            withItemAt: context.pluginWorkDirectory.appending(file.lastComponent).fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
    }
    
    private func prefixSQLCipherFile(at file: Path, using symbols: [Substring], in context: PluginContext) async throws {
        do { // Make sure the file handles are closed before we move the output into place.
            let reader = try FileHandle(forReadingFrom: file.fileUrl)
            defer { try? reader.close() }
            
            let outputFile = context.pluginWorkDirectory.appending(file.lastComponent)
            // `FileHandle(forWritingTo:)` refuses to create new files.
            FileManager.default.createFile(atPath: outputFile.string, contents: nil)
            let writer = try FileHandle(forWritingTo: outputFile.fileUrl)
            defer { try? writer.close() }
            
            // Filter out SQLcipher-added symbols to keep text substitution simple.
            let symbs: [Substring] = symbols.filter { !$0.contains("sqlcipher") }
            // We know what prefix we want.
            let minimalCommonPrefix = "sqlite3_"
            
            if self.verbose { Diagnostics.progress("Prefixing symbols in \(file.lastComponent) (minimum prefix \(minimalCommonPrefix))") }
            for try await line in reader.bytes.keepingEmptySubsequencesLines {
                let oline = line.contains(minimalCommonPrefix) ?
                    symbs.reduce(line, { $0.replacingOccurrences(of: $1, with: "\(Self.vendorPrefix)_\($1)") }) :
                    line
                
                try writer.write(contentsOf: Array("\(oline)\n".utf8))
            }
        }
        
        try FileManager.default.replaceItem(
            at: file.fileUrl,
            withItemAt: context.pluginWorkDirectory.appending(file.lastComponent).fileUrl,
            backupItemName: nil, resultingItemURL: nil
        )
    }
}
#else
@main
struct VendorSQLite: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        Diagnostics.error("This plugin is not implemented on non-Apple platforms.")
        throw VendoringError("This plugin is not implemented on non-Apple platforms.")
    }
}
#endif

struct VendoringError: Error, ExpressibleByStringLiteral, CustomStringConvertible {
    let description: String
    
    init(stringLiteral value: String) { self.description = value }
    init(_ description: String) { self.description = description }
}
