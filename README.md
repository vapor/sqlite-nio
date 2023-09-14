<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://user-images.githubusercontent.com/1130717/268050010-4fe2d383-61b0-4ae6-9fd4-d795492686f6.png">
  <source media="(prefers-color-scheme: light)" srcset="https://user-images.githubusercontent.com/1130717/268049911-75f4e82e-6ccb-4f81-874f-95a57eef2935.png">
  <img src="https://user-images.githubusercontent.com/1130717/268049911-75f4e82e-6ccb-4f81-874f-95a57eef2935.png" height="96" alt="SQLiteNIO">
</picture> 
<br>
<br>
<a name=""><img src="https://img.shields.io/badge/sswg-incubating-green.svg" alt="SSWG Incubation"></a>
<a href="https://api.vapor.codes/sqlitenio/documentation/sqlitenio/"><img src="https://img.shields.io/badge/read_the-docs-2196f3.svg" alt="Documentation"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License"></a>
<a href="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml"><img src="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml/badge.svg" alt="Continuous Integration"></a>
<a href="https://swift.org"><img src="https://img.shields.io/badge/swift-5.7-brightgreen.svg" alt="Swift 5.7"></a>
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
