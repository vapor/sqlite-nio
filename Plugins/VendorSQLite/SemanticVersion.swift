#if canImport(Darwin)

struct SemanticVersion: LosslessStringConvertible, Comparable, Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ description: String) { self.init(from: description) }
    init?(from string: some StringProtocol) {
        let version = string.split(separator: ".")
        guard version.count == 3,
              let major = Int(version[0]), let minor = Int(version[1]), let patch = Int(version[2])
        else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(self.major).\(self.minor).\(self.patch)" }
    
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major != rhs.major ? lhs.major < rhs.major : (
               lhs.minor != rhs.minor ? lhs.minor < rhs.minor : (
               lhs.patch != rhs.patch ? lhs.patch < rhs.patch : false))
    }
}

#endif
