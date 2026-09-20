// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "K673",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "K673Kit"),
        .executableTarget(name: "k673ctl", dependencies: ["K673Kit"]),
        .executableTarget(name: "K673App", dependencies: ["K673Kit"]),
    ]
)
