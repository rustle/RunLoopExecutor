// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RunLoopExecutor",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "RunLoopExecutor",
            targets: ["RunLoopExecutor"]
        ),
        .library(
            name: "RunLoopExecutorPool",
            targets: ["RunLoopExecutorPool"]
        ),
    ],
    targets: [
        .target(
            name: "RunLoopExecutor"
        ),
        .target(
            name: "RunLoopExecutorPool",
            dependencies: [
                "RunLoopExecutor",
            ]
        ),
        .testTarget(
            name: "RunLoopExecutorTests",
            dependencies: ["RunLoopExecutor"]
        ),
        .testTarget(
            name: "RunLoopExecutorPoolTests",
            dependencies: ["RunLoopExecutorPool"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
