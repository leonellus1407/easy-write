// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyWrite",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure value logic, deliberately free of AppKit and FoundationModels so it can be
        // unit tested without a running NSApplication or Apple Intelligence.
        .target(
            name: "EasyWriteCore",
            path: "Sources/EasyWriteCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "EasyWrite",
            dependencies: ["EasyWriteCore"],
            path: "Sources/EasyWrite",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "EasyWriteCoreTests",
            dependencies: ["EasyWriteCore"],
            path: "Tests/EasyWriteCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
