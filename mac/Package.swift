// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibePal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibePal",
            path: "Sources/VibePal",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "VibePalTests", dependencies: ["VibePal"])
    ]
)
