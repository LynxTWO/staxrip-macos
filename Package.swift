// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StaxRipMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StaxRipMac", targets: ["StaxRipMac"])],
    targets: [.executableTarget(name: "StaxRipMac"), .testTarget(name: "StaxRipMacTests", dependencies: ["StaxRipMac"])],
    swiftLanguageModes: [.v5]
)
