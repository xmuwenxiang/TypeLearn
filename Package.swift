// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TypeLearn",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TypeLearn",
            path: "Sources/TypeLearn"
        )
    ]
)
