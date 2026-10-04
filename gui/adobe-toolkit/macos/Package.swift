// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdobeToolkit",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "AdobeToolkit", targets: ["AdobeToolkit"])],
    targets: [
        .target(name: "ToolkitCore", resources: [.copy("Resources/Fixtures"), .copy("Resources/Backend")]),
        .executableTarget(name: "AdobeToolkit", dependencies: ["ToolkitCore"]),
        .testTarget(name: "ToolkitCoreTests", dependencies: ["ToolkitCore"]),
        .testTarget(name: "AdobeToolkitTests", dependencies: ["AdobeToolkit", "ToolkitCore"])
    ]
)
