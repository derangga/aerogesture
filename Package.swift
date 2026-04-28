// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "aerogesture",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "aerogesture",
            dependencies: ["TOMLKit"],
            path: "Sources/aerogesture",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
