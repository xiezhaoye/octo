// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeFileManager",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DualPane", targets: ["DualPane"])],
    targets: [
        .target(name: "FileManagerCore"),
        .executableTarget(name: "DualPane", dependencies: ["FileManagerCore"], resources: [.process("Resources")]),
        .testTarget(name: "FileManagerCoreTests", dependencies: ["FileManagerCore"])
    ],
    swiftLanguageModes: [.v5]
)
