#if canImport(Darwin)

// N.B.: If we wanted a complete representation of the symbol graph type, we'd add a swift-docc-symbolkit
// dependency. This type includes _only_ the pieces we need for vendoring, which isn't very many.
struct SymbolGraph: Codable {
    struct Symbol: Codable {
        struct Identifier: Codable { let precise: String }
        struct Kind: Codable { let identifier: String }

        let identifier: Identifier
        let kind: Kind
    }
    
    let symbols: [Symbol]
}

#endif
