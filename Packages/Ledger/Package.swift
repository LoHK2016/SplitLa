// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledger",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Ledger", targets: ["Ledger"])],
    targets: [
        .target(name: "Ledger"),
        .testTarget(name: "LedgerTests", dependencies: ["Ledger"]),
    ]
)
