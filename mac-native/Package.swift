// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GameRoomMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GameRoomMac", targets: ["GameRoomMac"])
    ],
    targets: [
        .executableTarget(
            name: "GameRoomMac",
            path: "Sources/GameRoomMac"
        )
    ]
)
