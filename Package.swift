// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "GrokDeck",
            targets: ["GrokDeck"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GrokDeck",
            path: "GrokDeck",
            exclude: ["GrokDeckApp.swift"], // We use AppKit entry point instead
            resources: [
                .process("Resources")
            ]
        )
    ]
)