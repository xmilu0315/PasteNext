// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteNext",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PasteNext", targets: ["PasteNext"])],
    // The test suite lives inside the app: `PasteNext --self-test` runs it with
    // no XCTest dependency, so it works with the Command Line Tools toolchain.
    targets: [
        .executableTarget(name: "PasteNext", path: "Sources/PasteNext")
    ]
)
