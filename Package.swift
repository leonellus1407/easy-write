// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyWrite",
    // 26.4 is what Apple Translate needs: TranslationSession.Strategy and the initializer that
    // takes one are gated there, while the rest of the framework is 26.0.
    platforms: [.macOS("26.4")],
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
