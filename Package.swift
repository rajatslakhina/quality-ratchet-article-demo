// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QualityRatchet",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QualityRatchet", targets: ["QualityRatchet"])
    ],
    targets: [
        .target(name: "QualityRatchet"),
        .testTarget(name: "QualityRatchetTests", dependencies: ["QualityRatchet"])
    ]
)
