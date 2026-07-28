import Foundation
import PackagePlugin

#if canImport(Darwin)
@main
struct VendorSQLite: CommandPlugin {
    // Constants
    static let usage = """
        SQLite3 vendoring command

        This command provides support for updating the embedded C sqlite3 library.

        Options:
          -h, --help              Show this help.
          -v, --verbose           Output detailed progress information.
          --force                 Run the vendoring process even if the currently embedded version
                                    is already up to date.
        """
    static let sqliteURL = URL(string: "https://sqlite.org")!
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
        Self.verbose = extractor.extractFlag(named: "verbose", shortForm: "v") > 0

        guard extractor.remainingArguments.isEmpty else {
            for f in extractor.unextractedOptionsOrFlags { Diagnostics.error("Unknown option '\(f)'.") }
            if extractor.remainingArguments.count > extractor.unextractedOptionsOrFlags.count {
                Diagnostics.error("This command does not accept any arguments.")
            }
            return print(Self.usage)
        }
        
        // Clear work directory
        for item in try FileManager.default.contentsOfDirectory(at: context.pluginWorkDirectoryURL, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) {
            try FileManager.default.removeItem(at: item)
        }
        
        // Find C target
        guard let target = try context.package.targets(named: ["VaporCSQLite"]).first.flatMap({ $0 as? ClangSourceModuleTarget }) else {
            throw VendoringError("Unable to find the VaporCSQLite target in package.")
        }
        if self.verbose { Diagnostics.progress("Found VaporCSQLite target with path \(target.directoryURL.path(percentEncoded: false))") }

        // Load current version
        guard let line = try await target.directoryURL.appending(component: "version.txt").lines.first(where: { !$0.starts(with: "//") }),
              let currentVersion = SemanticVersion(line)
        else {
            throw VendoringError("Could not read version stamp.")
        }
        if self.verbose { Diagnostics.progress("Current version: \(currentVersion)") }
        
        // Check for new versions
        let latestData = try await self.getLatestDownloadInfo()
        
        guard latestData.version.major == currentVersion.major else {
            throw VendoringError("Latest version \(latestData.version) is not same major version as current \(currentVersion)")
        }
        guard force || latestData.version > currentVersion else {
            throw VendoringError("Latest version \(latestData.version) is not newer than current \(currentVersion)")
        }
        if self.verbose { Diagnostics.progress("Found valid update: \(latestData.version)") }
        
        // Retrieve new sources, unzip, apply patches, replace current sources.
        try await self.downloadUnpackPatch(latestData, context: context, target: target)
        
        // Extract symbol graph from new sources.
        let symbols = try await self.extractSymbols(for: target, context: context)

        // MARK: Prefix the symbols in the new sources.
        try await self.prefixFile(
            at: target.publicHeadersDirectoryURL!.appending(component: "\(Self.vendorPrefix)_sqlite3.h"),
            using: symbols,
            in: context
        )
        try await self.prefixFile(
            at: target.directoryURL.appending(component: "\(Self.vendorPrefix)_sqlite3.c"),
            using: symbols,
            in: context
        )
        
        // Stamp sources with updated version info.
        try """
        // This directory is generated from SQLite sources downloaded from \(latestData.downloadURL.absoluteString)
        \(latestData.version)
        
        """.write(to: target.directoryURL.appending(component: "version.txt"), atomically: true, encoding: .utf8)

        Diagnostics.progress("Upgraded from \(currentVersion) to \(latestData.version)")
    }
    
    private func getLatestDownloadInfo() async throws -> Sqlite3ProductInfo {
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
            throw VendoringError("DNS error when trying to load downloads list. You probably need to use --disable-sandbox. Underlying error: \(error)")
        }
        
        if foundCSV {
            throw VendoringError("Could not find latest version on download page.")
        } else {
            throw VendoringError("Failed to find product CSV table on download page.")
        }
    }
    
    private func downloadUnpackPatch(
        _ latestData: Sqlite3ProductInfo,
        context: PluginContext,
        target: ClangSourceModuleTarget
    ) async throws {
        let zipURL = context.pluginWorkDirectoryURL.appending(component: latestData.filename)

        if self.verbose { Diagnostics.progress("Starting download from \(latestData.downloadURL.absoluteString)") }
        try Process.run("curl", "-f\(self.verbose ? "" : "sS")Lo", "\(zipURL.path(percentEncoded: false))", latestData.downloadURL.absoluteString)

        let zipSize = try zipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard zipSize == latestData.sizeInBytes else {
            throw VendoringError("Download \(zipURL.path(percentEncoded: false)) wrong size (expected \(latestData.sizeInBytes), got \(zipSize ?? -1))")
        }

        let sha3Hash = try await Process.popen("sha3sum", "-a", "256", "\(zipURL.path(percentEncoded: false))").prefix(while: { !$0.isWhitespace })
        guard sha3Hash == latestData.sha3Hash else {
            throw VendoringError("Download \(zipURL.path(percentEncoded: false)) has wrong hash (expected \(latestData.sha3Hash), got \(sha3Hash))")
        }

        try Process.run("unzip", "-\(self.verbose ? "" : "q")j", "-d", "\(context.pluginWorkDirectoryURL.path(percentEncoded: false))", "\(zipURL.path(percentEncoded: false))")
        try Process.run("patch", "-\(self.verbose ? "" : "s")d", "\(context.pluginWorkDirectoryURL.path(percentEncoded: false))", "-p1", "-u", "-i", "\(URL(filePath: #filePath).deletingLastPathComponent().appending(component: "001-warnings-and-data-race.patch"))"
        )

        try FileManager.default.replaceItem(
            at: target.publicHeadersDirectoryURL!.appending(component: "\(Self.vendorPrefix)_sqlite3.h"),
            withItemAt: context.pluginWorkDirectoryURL.appending(component: "sqlite3.h"),
            backupItemName: nil, resultingItemURL: nil
        )
        try FileManager.default.replaceItem(
            at: target.directoryURL.appending(component: "\(Self.vendorPrefix)_sqlite3.c"),
            withItemAt: context.pluginWorkDirectoryURL.appending(component: "sqlite3.c"),
            backupItemName: nil, resultingItemURL: nil
        )
    }

    private func extractSymbols(for target: any PackagePlugin.SourceModuleTarget, context: PluginContext) async throws -> [Substring] {
        // Get a list of relevant symbols from the SPM symbol graph.
        if self.verbose { Diagnostics.progress("Starting symbol graph generation") }
        let symbolGraphFile = try self.packageManager.getSymbolGraph(for: target, options: .init(
            minimumAccessLevel: .public, includeSynthesized: false, includeSPI: false, emitExtensionBlocks: false
        )).directoryURL.appending(component: "\(target.name).symbols.json")

        let symbolGraph = try JSONDecoder().decode(SymbolGraph.self, from: Data(contentsOf: symbolGraphFile))
        
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

        let objDir = context.package.directoryURL.appending(components: ".build", "out", "Products", "Debug")
        var objSymbols: Set<Substring> = []
        for object in try FileManager.default.contentsOfDirectory(at: objDir, includingPropertiesForKeys: nil)
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
    
    private func prefixFile(at file: URL, using symbols: [Substring], in context: PluginContext) async throws {
        do { // Make sure the file handles are closed before we move the output into place.
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            
            let outputFile = context.pluginWorkDirectoryURL.appending(component: file.lastPathComponent)
            // `FileHandle(forWritingTo:)` refuses to create new files.
            FileManager.default.createFile(atPath: outputFile.path(percentEncoded: false), contents: nil)
            let writer = try FileHandle(forWritingTo: outputFile)
            defer { try? writer.close() }
            
            let minimalCommonPrefix = symbols.reduce(symbols[0]) { $1.commonPrefix(with: $0, options: .literal)[...] }
            
            Diagnostics.progress("Prefixing symbols in \(file.lastPathComponent) (minimum prefix \(minimalCommonPrefix))...")
            for try await line in reader.bytes.keepingEmptySubsequencesLines {
                let oline = line.contains(minimalCommonPrefix) ?
                    symbols.reduce(line, { $0.replacingOccurrences(of: $1, with: "\(Self.vendorPrefix)_\($1)") }) :
                    line
                
                try writer.write(contentsOf: Array("\(oline)\n".utf8))
            }
        }
        
        try FileManager.default.replaceItem(
            at: file,
            withItemAt: context.pluginWorkDirectoryURL.appending(component: file.lastPathComponent),
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

