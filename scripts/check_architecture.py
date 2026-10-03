"""Verify SwiftPM's explicit layer boundaries and cycles; no runtime mocks."""
from pathlib import Path
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
print("Architecture checks passed: explicit imports, layers, cycles, platform-independent Core")
