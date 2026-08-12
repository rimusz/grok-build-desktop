// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokBuild",
    platforms: [.macOS("26.0")],
    products: [
        .executable(
            name: "GrokBuild",
            targets: ["GrokBuild"]
        ),
        .executable(
            name: "GrokBuildComputerUseMCP",
            targets: ["GrokBuildComputerUseMCP"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GrokBuild",
            path: "GrokBuild",
            exclude: [
                "GrokBuildApp.swift", // AppKit entry point instead
                // Packaged via scripts/bundle-cursor-bridge.sh (npm install + copy into .app)
                "Resources/CursorBridge",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Skills/grokbuild-browser-control"),
                .copy("Resources/Skills/grokbuild-computer-use"),
                .copy("Resources/Skills/grokbuild-desktop"),
                .copy("Resources/Skills/grokbuild-grok-web"),
            ]
        ),
        .executableTarget(
            name: "GrokBuildComputerUseMCP",
            path: "GrokBuildComputerUseMCP"
        ),
        .testTarget(
            name: "GrokBuildTests",
            dependencies: ["GrokBuild"]
        )
    ]
)