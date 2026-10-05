"""Verify SwiftPM's explicit layer boundaries and cycles; no runtime mocks."""
from pathlib import Path
import ast
import json
import re
import subprocess

root = Path(__file__).resolve().parent.parent
package = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=root))
targets = {target["name"]: target for target in package["targets"]}
graph = {}
for name, target in targets.items():
    dependencies = {entry["byName"][0] for entry in target["dependencies"] if "byName" in entry}
    graph[name] = dependencies
    for source in (root / "Sources" / name).glob("*.swift"):
        imports = set(re.findall(r"^import (Manga\w+)", source.read_text(), re.MULTILINE))
        illegal = imports - dependencies
        if illegal:
            raise SystemExit(f"{source.relative_to(root)} imports undeclared targets: {sorted(illegal)}")

allowed = {
    "MangaLadaCore": set(),
    "MangaLadaImport": {"MangaLadaCore"},
    "MangaLadaBallons": {"MangaLadaCore"},
    "MangaLadaVision": {"MangaLadaCore"},
    "MangaLadaRendering": {"MangaLadaCore"},
    "MangaLadaViewerUI": {"MangaLadaCore"},
    "MangaLadaWorkflow": {"MangaLadaCore", "MangaLadaBallons", "MangaLadaVision", "MangaLadaRendering"},
    "MangaReaderApp": {"MangaLadaCore", "MangaLadaImport", "MangaLadaViewerUI"},
    "MangaLadaApp": {"MangaLadaCore", "MangaLadaImport", "MangaLadaRendering", "MangaLadaWorkflow", "MangaLadaViewerUI"},
}
for target, permitted in allowed.items():
    if graph[target] - permitted:
        raise SystemExit(f"Layer violation: {target} -> {sorted(graph[target] - permitted)}")

adapters = root / "Sources" / "MangaLadaBallons" / "Resources"
python_modules = {path.stem: path for path in adapters.glob("*.py")}
python_allowed = {
    "japanese_engine_worker": {"balloon_geometry", "text_region_kind", "text_region_geometry", "optical_effects", "flat_background", "sentence_punctuation", "erase_supplemental_text", "detection_refinement", "balloon_partition", "balloon_lobes", "balloon_recovery", "lettering_regions", "hayai_lettering", "region_ocr"},
    "balloon_recovery": {"balloon_candidates", "detection_refinement", "text_region_geometry"},
    "balloon_candidates": {"dotted_balloon"},
    "region_ocr": {"lettering_ocr"},
    "lettering_ocr": set(), "hayai_lettering": set(),
    "lettering_regions": {"balloon_candidates", "lettering_ocr"},
    "detection_refinement": {"balloon_geometry", "text_region_geometry"},
    "optical_effects": {"erase_supplemental_text", "text_region_kind", "text_region_geometry"},
    "sentence_punctuation": {"text_region_geometry"}, "text_region_geometry": set(),
    "balloon_lobes": {"balloon_geometry", "detection_refinement"}, "balloon_partition": set(),
    "balloon_geometry": {"text_region_geometry", "dotted_balloon"}, "dotted_balloon": set(),
    "text_region_kind": {"text_region_geometry"},
    "erase_supplemental_text": {"flat_background"}, "flat_background": set(),
}
for module, path in python_modules.items():
    imports = set()
    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module.split(".")[0])
        elif isinstance(node, ast.Import):
            imports.update(alias.name.split(".")[0] for alias in node.names)
    dependencies = imports & python_modules.keys()
    if dependencies - python_allowed.get(module, set()):
        raise SystemExit(f"Python adapter boundary violation: {module} -> {sorted(dependencies)}")
    graph["python:" + module] = {"python:" + dependency for dependency in dependencies}


def visit(name: str, active: set[str], checked: set[str]) -> None:
    if name in active:
        raise SystemExit(f"Dependency cycle at {name}")
    if name in checked:
        return
    for dependency in graph.get(name, set()):
        visit(dependency, active | {name}, checked)
    checked.add(name)


checked: set[str] = set()
for name in graph:
    visit(name, set(), checked)
for source in (root / "Sources" / "MangaLadaCore").glob("*.swift"):
    if re.search(r"^import (AppKit|SwiftUI|Vision|MangaLadaApp)", source.read_text(), re.MULTILINE):
        raise SystemExit(f"Core platform dependency: {source.name}")
print("Architecture checks passed: Swift/Python imports, layers, cycles, platform-independent Core")
