// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DevFlow", targets: ["DevFlowApp"]), .executable(name: "DevFlowChecks", targets: ["DevFlowChecks"]), .executable(name: "DevFlowEvidence", targets: ["DevFlowEvidence"]), .library(name: "DevFlowCore", targets: ["DevFlowCore"])],
    targets: [
        .target(name: "DevFlowCore"),
        .executableTarget(name: "DevFlowApp", dependencies: ["DevFlowCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "DevFlowEvidence", dependencies: ["DevFlowCore"]),
        .executableTarget(name: "DevFlowChecks", dependencies: ["DevFlowCore"], path: "Tests/DevFlowCoreTests")
    ]
)
