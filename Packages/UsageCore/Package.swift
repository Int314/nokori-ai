// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "UsageCore", defaultLocalization: "en", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "UsageCore", targets: ["UsageCore"]), .library(name: "UsageUI", targets: ["UsageUI"])],
    targets: [
        .target(name: "UsageCore", resources: [.process("Resources")]),
        .target(name: "UsageUI", dependencies: ["UsageCore"], resources: [.process("Resources")]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")])
    ])
