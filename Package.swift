// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TicTacToeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TicTacToeCore",
            targets: ["TicTacToeCore"]
        ),
    ],
    targets: [
        .target(
            name: "TicTacToeCore",
            path: "Sources"
        ),
        .testTarget(
            name: "TicTacToeCoreTests",
            dependencies: ["TicTacToeCore"],
            path: "Tests"
        ),
    ]
)
