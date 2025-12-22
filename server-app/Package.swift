// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhotoShareServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "PhotoShareServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "PhotoShareServer"
        ),
    ]
)

