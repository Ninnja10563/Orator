// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orator",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PresentationCore", targets: ["PresentationCore"]), .executable(name: "Orator", targets: ["Orator"])],
    targets: [
        .target(name: "PresentationCore"),
        .executableTarget(name: "Orator", dependencies: ["PresentationCore"]),
        .testTarget(name: "PresentationCoreTests", dependencies: ["PresentationCore"], resources: [.copy("Fixtures")])
    ]
)
