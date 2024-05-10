<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/vapor/sqlite-nio/assets/1130717/84529505-7534-456f-a065-c06cc84f3c0d">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/vapor/sqlite-nio/assets/1130717/a839372c-5f79-4e59-8cf7-db44af8f20a9">
  <img src="https://github.com/vapor/sqlite-nio/assets/1130717/a839372c-5f79-4e59-8cf7-db44af8f20a9" height="96" alt="SQLiteNIO">
</picture> 
<br>
<br>
<a href="https://docs.vapor.codes/4.0/"><img src="https://design.vapor.codes/images/readthedocs.svg" alt="Documentation"></a>
<a href="https://discord.gg/vapor"><img src="https://design.vapor.codes/images/discordchat.svg" alt="Team Chat"></a>
<a href="LICENSE"><img src="https://design.vapor.codes/images/mitlicense.svg" alt="MIT License"></a>
<a href="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/vapor/sqlite-nio/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration"></a>
<a href="https://codecov.io/github/vapor/sqlite-nio"><img src="https://img.shields.io/codecov/c/github/vapor/sqlite-nio?style=plastic&logo=codecov&label=codecov"></a>
<a href="https://swift.org"><img src="https://design.vapor.codes/images/swift58up.svg" alt="Swift 5.8+"></a>
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
