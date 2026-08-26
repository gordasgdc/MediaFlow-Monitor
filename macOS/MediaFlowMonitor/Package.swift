// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaFlowMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MediaFlowMonitor",
            path: "Sources/MediaFlowMonitor",
            resources: [.process("Resources/Localization")]
        )
    ]
)
