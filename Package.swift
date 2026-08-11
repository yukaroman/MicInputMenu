// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MicInputMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MicInputMenu", targets: ["MicInputMenu"])
    ],
    targets: [
        .executableTarget(name: "MicInputMenu")
    ],
    swiftLanguageModes: [.v5]
)
