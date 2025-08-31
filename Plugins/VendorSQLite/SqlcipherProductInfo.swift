#if canImport(Darwin)

import Foundation

struct SqlcipherProductInfo {
    let version: SemanticVersion
    let downloadURL: URL
    let filename: String
    let tagName: String

    init(tagName: String, tarballURL: String) throws {
        // SQLCipher versions are like "v4.9.0"
        let versionString = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        
        guard let version = SemanticVersion(versionString) else {
            throw VendoringError("Invalid SQLCipher version \(versionString)")
        }
        guard let downloadURL = URL(string: tarballURL) else {
            throw VendoringError("Invalid SQLCipher tarball URL \(tarballURL)")
        }

        self.version = version
        self.downloadURL = downloadURL
        self.filename = downloadURL.lastPathComponent
        self.tagName = tagName
    }
}

#endif 