// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteNext",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PasteNext", targets: ["PasteNext"])],
    targets: [
        .executableTarget(name: "PasteNext", path: "Sources/PasteNext"),
        .testTarget(name: "PasteNextTests", dependencies: ["PasteNext"], path: "Tests/PasteNextTests")
    ]
)
