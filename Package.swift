// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokBuild",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "GrokBuild",
            targets: ["GrokBuild"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GrokBuild",
            path: "GrokBuild",
            exclude: ["GrokBuildApp.swift"], // We use AppKit entry point instead
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GrokBuildTests",
            dependencies: ["GrokBuild"]
        )
    ]
)