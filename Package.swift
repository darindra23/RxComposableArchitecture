// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RxComposableArchitecture",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "RxComposableArchitecture",
            targets: ["RxComposableArchitecture"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ReactiveX/RxSwift", from: "5.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.8.1"),
        .package(name: "Benchmark", url: "https://github.com/google/swift-benchmark", from: "0.1.0"),
        .package(url: "https://github.com/darindra23/xctest-dynamic-overlay", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "RxComposableArchitecture",
            dependencies: [
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxRelay", package: "RxSwift"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ]
        ),
        .testTarget(
            name: "RxComposableArchitectureTests",
            dependencies: ["RxComposableArchitecture"]
        ),
        .executableTarget(
            name: "RxComposableArchitecture-Benchmark",
            dependencies: [
                "RxComposableArchitecture",
                .product(name: "Benchmark", package: "Benchmark"),
            ]
        ),
    ]
)
