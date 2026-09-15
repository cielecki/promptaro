// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptPalette",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PromptPalette", targets: ["PromptPalette"])],
    targets: [
        .target(name: "PromptCore"),
        .executableTarget(name: "PromptPalette", dependencies: ["PromptCore"]),
        .testTarget(name: "PromptCoreTests", dependencies: ["PromptCore"]),
        .testTarget(name: "PromptPaletteTests", dependencies: ["PromptPalette"])
    ],
    swiftLanguageModes: [.v5]
)
