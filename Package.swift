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
        .executable(name: "MangaLadaBallonsChecks", targets: ["MangaLadaBallonsChecks"]),
        .executable(name: "MangaLadaWorkflowChecks", targets: ["MangaLadaWorkflowChecks"]),
        .executable(name: "MangaLadaImportChecks", targets: ["MangaLadaImportChecks"]),
        .executable(name: "MangaReader", targets: ["MangaReaderApp"])
    ],
    targets: [
        .target(
            name: "MangaLadaCore",
            resources: [.copy("Resources/sound-effect-lexicon.json"), .copy("Resources/Licenses")]
        ),
        .target(
            name: "MangaLadaVision",
            dependencies: ["MangaLadaCore"]
        ),
        .target(
            name: "MangaLadaRendering",
            dependencies: ["MangaLadaCore"],
            resources: [.copy("Resources/Fonts"), .copy("Resources/sound-effect-styles.json")]
        ),
        .target(
            name: "MangaLadaBallons",
            dependencies: ["MangaLadaCore"],
            resources: [.copy("Resources/erase_supplemental_text.py"), .copy("Resources/japanese_engine_worker.py"),
                        .copy("Resources/balloon_geometry.py"), .copy("Resources/text_region_kind.py"), .copy("Resources/optical_effects.py"),
                        .copy("Resources/detection_refinement.py"), .copy("Resources/balloon_lobes.py"), .copy("Resources/balloon_partition.py"),
                        .copy("Resources/dotted_balloon.py"), .copy("Resources/balloon_candidates.py"), .copy("Resources/balloon_recovery.py"),
                        .copy("Resources/flat_background.py"), .copy("Resources/sentence_punctuation.py"), .copy("Resources/balloon_erase_mask.py"),
                        .copy("Resources/text_region_geometry.py"), .copy("Resources/lettering_ocr.py"),
                        .copy("Resources/lettering_regions.py"), .copy("Resources/hayai_lettering.py"), .copy("Resources/region_ocr.py"),
                        .copy("Resources/text_detection.py"), .copy("Resources/manga_text_detector.py"), .copy("Resources/lettering_recovery.py"),
                        .copy("Resources/lettering_strokes.py")]
        ),
        .executableTarget(
            name: "MangaLadaApp",
            dependencies: ["MangaLadaCore", "MangaLadaRendering", "MangaLadaWorkflow", "MangaLadaImport", "MangaLadaViewerUI"]
        ),
        .target(name: "MangaLadaWorkflow", dependencies: ["MangaLadaCore", "MangaLadaBallons", "MangaLadaRendering", "MangaLadaVision"]),
        .target(name: "MangaLadaImport", dependencies: ["MangaLadaCore"]),
        .target(name: "MangaLadaViewerUI", dependencies: ["MangaLadaCore"]),
        .executableTarget(name: "MangaReaderApp", dependencies: ["MangaLadaCore", "MangaLadaImport", "MangaLadaViewerUI"]),
        .executableTarget(name: "MangaLadaWorkflowChecks", dependencies: ["MangaLadaCore", "MangaLadaImport", "MangaLadaRendering", "MangaLadaBallons", "MangaLadaWorkflow"]),
        .executableTarget(name: "MangaLadaImportChecks", dependencies: ["MangaLadaCore", "MangaLadaImport", "MangaLadaWorkflow", "MangaLadaViewerUI"]),
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
            dependencies: ["MangaLadaCore", "MangaLadaBallons", "MangaLadaRendering"]
        )
    ]
)
