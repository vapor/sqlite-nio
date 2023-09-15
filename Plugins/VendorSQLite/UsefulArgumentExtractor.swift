#if canImport(Darwin)

/// Exactly the same as SPM's builtin `ArgumentExtractor`, except it also (mostly) understands single-character short options.
public struct UsefulArgumentExtractor {
    private var args: [String]
    private let literals: [String]

    public init(_ arguments: [String]) {
        let parts = arguments.split(separator: "--", maxSplits: 1, omittingEmptySubsequences: false)
        self.args = Array(parts[0])
        self.literals = Array(parts.count == 2 ? parts[1] : [])
    }

    public mutating func extractOption(named name: String, shortForm: String? = nil) -> [String] {
        var values: [String] = [], idx = self.args.startIndex
        
        while idx < self.args.endIndex {
            if self.args[idx] == "--\(name)" || self.args[idx] == shortForm.map({ "-\($0)" }) {
                self.args.remove(at: idx)
                if idx < self.args.endIndex { values.append(self.args.remove(at: idx)) }
            } else if self.args[idx].starts(with: "--\(name)=") {
                values.append(String(self.args.remove(at: idx).dropFirst(2 + name.count + 1)))
            } else if let shortForm, args[idx].starts(with: "-\(shortForm)") {
                values.append(String(self.args.remove(at: idx).dropFirst(1 + shortForm.count)))
            } else {
                self.args.formIndex(after: &idx)
            }
        }
        return values
    }

    public mutating func extractFlag(named name: String, shortForm: String? = nil) -> Int {
        var count = 0, idx = self.args.startIndex
        
        while idx < self.args.endIndex {
            if self.args[idx] == "--\(name)" || self.args[idx] == shortForm.map({ "-\($0)" }) {
                self.args.remove(at: idx)
                count += 1
            } else {
                self.args.formIndex(after: &idx)
            }
        }
        return count
    }

    public var unextractedOptionsOrFlags: [String] { self.args.filter { $0.starts(with: "-") && $0 != "-" } }
    public var remainingArguments: [String] { self.args + self.literals }
}

#endif
