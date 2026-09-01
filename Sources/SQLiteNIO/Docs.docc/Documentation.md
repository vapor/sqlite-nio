# ``SQLiteNIO``

@Metadata {
    @TitleHeading(Package)
}

🪶 Non-blocking Swift client for [SQLite](https://sqlite.org) built on Swift Concurrency.

## Using SQLiteNIO

Use standard SwiftPM syntax to include SQLiteNIO as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0")
]
```

### Supported Platforms

SQLiteNIO supports all platforms with a Swift 6.1+ toolchain. At the time of this writing, these include:

- Ubuntu 22.04+
- macOS 15+
- iOS 18+
- tvOS 18+, watchOS 11+, and visionOS 2+
