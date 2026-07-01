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
        .executable(name: "MangaLadaRenderingChecks", targets: ["MangaLadaRenderingChecks"]),
        .executable(name: "MangaLadaBallonsChecks", targets: ["MangaLadaBallonsChecks"])
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
        .target(
            name: "MangaLadaBallons",
            dependencies: ["MangaLadaCore"]
        ),
        .executableTarget(
            name: "MangaLadaApp",
            dependencies: ["MangaLadaCore", "MangaLadaVision", "MangaLadaRendering", "MangaLadaBallons"]
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
        ),
        .executableTarget(
            name: "MangaLadaBallonsChecks",
            dependencies: ["MangaLadaCore", "MangaLadaBallons"]
        )
    ]
)
