<p align="center">
    <img 
        src="https://user-images.githubusercontent.com/1342803/58997662-a5209e80-87cb-11e9-859d-e04ec148fd05.png" 
        height="64" 
        alt="SQLiteNIO"
    >
    <br>
    <br>
    <a href="https://docs.vapor.codes/4.0/">
        <img src="http://img.shields.io/badge/read_the-docs-2196f3.svg" alt="Documentation">
    </a>
    <a href="https://discord.gg/vapor">
        <img src="https://img.shields.io/discord/431917998102675485.svg" alt="Team Chat">
    </a>
    <a href="LICENSE">
        <img src="http://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License">
    </a>
    <a href="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml">
        <img src="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml/badge.svg?action=push" alt="Continuous Integration">
    </a>
    <a href="https://swift.org">
        <img src="http://img.shields.io/badge/swift-5.6-brightgreen.svg" alt="Swift 5.6">
    </a>
    <a href="https://swift.org">
        <img src="http://img.shields.io/badge/swift-5.8-brightgreen.svg" alt="Swift 5.8">
    </a>
</p>

<br>

🐬 Non-blocking, event-driven Swift client for [SQLite](https://sqlite.org) built on [SwiftNIO](https://github.com/apple/swift-nio).

## Using SQLiteNIO

Use standard SwiftPM syntax to include SQLiteNIO as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0")
]
```

### Supported Platforms

SQLiteNIO supports all platforms on which NIO itself works. At the time of this writing, these include:

- Ubuntu 20.04+
- macOS 10.15+
- iOS 13+
- tvOS 13+ and watchOS 7+ (experimental)
