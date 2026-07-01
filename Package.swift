// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MangaLadaMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MangaLadaCore", targets: ["MangaLadaCore"]),
        .executable(name: "MangaLada", targets: ["MangaLadaApp"]),
        .executable(name: "MangaLadaCoreChecks", targets: ["MangaLadaCoreChecks"]),
        .executable(name: "MangaLadaVisionChecks", targets: ["MangaLadaVisionChecks"]),
        .executable(name: "MangaLadaRenderingChecks", targets: ["MangaLadaRenderingChecks"])
    ],
    targets: [
        .target(
            name: "MangaLadaCore"
        ),
        .target(
            name: "MangaLadaVision",
            dependencies: ["MangaLadaCore"]
        ),
        .target(
            name: "MangaLadaRendering",
            dependencies: ["MangaLadaCore"]
        ),
        .executableTarget(
            name: "MangaLadaApp",
            dependencies: ["MangaLadaCore", "MangaLadaVision", "MangaLadaRendering"]
        ),
        .executableTarget(
            name: "MangaLadaCoreChecks",
            dependencies: ["MangaLadaCore"]
        ),
        .executableTarget(
            name: "MangaLadaVisionChecks",
            dependencies: ["MangaLadaCore", "MangaLadaVision"]
        ),
        .executableTarget(
            name: "MangaLadaRenderingChecks",
            dependencies: ["MangaLadaCore", "MangaLadaRendering"]
        )
    ]
)
