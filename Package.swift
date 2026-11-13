// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenHalo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ScreenHalo", targets: ["ScreenHalo"])],
    targets: [
        .target(name: "HaloCore"),
        .executableTarget(name: "ScreenHalo", dependencies: ["HaloCore"]),
    ]
)
