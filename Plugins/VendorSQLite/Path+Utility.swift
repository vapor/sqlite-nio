import struct Foundation.URL
import PackagePlugin

extension PackagePlugin.Path {
    var fileUrl: URL { .init(fileURLWithPath: self.string, isDirectory: false) }
    var directoryUrl: URL { .init(fileURLWithPath: self.string, isDirectory: true) }
    func replacingLastComponent(with component: String) -> Path { self.removingLastComponent().appending(component) }
}
