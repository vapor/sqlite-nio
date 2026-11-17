<div align="center">
<img src="https://design.vapor.codes/images/vapor-sqlitenio.svg" height="96" alt="SQLiteNIO">
<br>

[![Documentation](https://design.vapor.codes/images/readthedocs.svg)](https://docs.vapor.codes/4.0/)
[![Team Chat](https://design.vapor.codes/images/discordchat.svg)](https://discord.gg/vapor)
[![MIT License](https://design.vapor.codes/images/mitlicense.svg)](./LICENSE)
[![Continuous Integration](https://img.shields.io/github/actions/workflow/status/vapor/sqlite-nio/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=ccc)](https://github.com/vapor/sqlite-nio/actions/workflows/test.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/vapor/sqlite-nio?style=plastic&logo=codecov&label=codecov)](https://codecov.io/github/vapor/sqlite-nio)
[![Swift 6.3+](https://design.vapor.codes/images/swift63up.svg)](https://swift.org)

</div>

<br>

🪶 Non-blocking Swift client for [SQLite](https://sqlite.org) built on Swift Concurrency.

## Using SQLiteNIO

Use standard SwiftPM syntax to include SQLiteNIO as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0")
]
```

### Supported Platforms

SQLiteNIO supports all platforms with a Swift 6.3+ toolchain. At the time of this writing, these include:

- Ubuntu 22.04+
- macOS 15+
- iOS 18+
- tvOS 18+, watchOS 11+, and visionOS 2+
