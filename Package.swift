// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RunLoopExecutor",
    platforms: [
        .macOS(.v15),
        .iOS(.v13)
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
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-atomics.git",
            .upToNextMajor(from: "1.2.0")
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
                .product(
                    name: "Atomics",
                    package: "swift-atomics"
                ),
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
