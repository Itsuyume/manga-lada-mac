#!/usr/bin/env python3
"""Import a downloaded official JMdict_e.gz into the runtime effect catalog.

Download: https://www.edrdg.org/pub/Nihongo/JMdict_e.gz
Run before releases to refresh dictionary data. No network access or model calls.
Curated entries without jmdictIDs win over imported spellings and are preserved.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import xml.etree.ElementTree as ET


def normalize(text):
    return unicodedata.normalize("NFKC", text).strip(" \t\r\n.!?。…・")


def kana_forms(text):
    text = normalize(text)
    if not re.fullmatch(r"[ぁ-ゖァ-ヶー]{2,20}", text):
        return set()
    hiragana = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)
    katakana = "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in hiragana)
    return {hiragana, katakana}


def automatic_form(text, senses):
    # A dictionary's on-mim tag also covers ordinary adverbs such as きっと.
    # Only isolated expressive forms become OCR candidates automatically.
    if any("interjection" in (p.text or "") for s in senses for p in s.findall("pos")):
        return False
    if re.fullmatch(r"[あいうえおぁぃぅぇぉはふへほんっアイウエオァィゥェォハフヘホンッー]+", text):
        return False
    return bool(re.fullmatch(r"(.{2,6})\1{1,3}", text)
                or re.search(r"[っッんン]$", text)
                or ("ー" in text and len(text) >= 3))


def import_entries(source, reserved):
    by_form = {}
    total = 0
    with gzip.open(source, "rb") as stream:
        for _, entry in ET.iterparse(stream, events=("end",)):
            if entry.tag != "entry":
                continue
            senses = entry.findall("sense")
            mimetic = [s for s in senses if any(m.text == "onomatopoeic or mimetic word" for m in s.findall("misc"))]
            if not mimetic:
                entry.clear()
                continue
            total += 1
            forms = set().union(*(kana_forms(r.text or "") for r in entry.findall("r_ele/reb")))
            glosses = list(dict.fromkeys(g.text for s in mimetic for g in s.findall("gloss") if g.text))
            if not glosses:
                raise ValueError("Mimetic entry has no English gloss: " + str(entry.findtext("ent_seq")))
            for form in sorted(forms - reserved):
                value = by_form.setdefault(form, {"glosses": [], "ids": [], "recognition": True})
                value["glosses"] += [g for g in glosses if g not in value["glosses"]]
                value["ids"].append(int(entry.findtext("ent_seq")))
                value["recognition"] &= len(mimetic) == len(senses) and automatic_form(form, senses)
            entry.clear()
    if not by_form:
        raise ValueError("Dictionary contains no usable mimetic readings")
    entries = []
    for form, value in sorted(by_form.items()):
        # Keep alternatives; this is not a one-meaning Korean replacement table.
        hint = "; ".join(value["glosses"][:12])
        if len(hint) > 600:
            hint = hint[:597].rsplit("; ", 1)[0] + "..."
        entries.append({"sources": [form], "meaning": hint, "recognition": value["recognition"],
                        "jmdictIDs": sorted(set(value["ids"]))})
    return entries, total


def update(source, catalog_path):
    catalog = json.loads(catalog_path.read_text())
    if catalog.get("version") != 1:
        raise ValueError("Unsupported catalog version")
    curated = [entry for entry in catalog["entries"] if "jmdictIDs" not in entry]
    reserved = {normalize(s) for entry in curated for s in entry["sources"]}
    imported, total = import_entries(source, reserved)
    with gzip.open(source, "rt") as stream:
        header = stream.read(60000)
    created = re.search(r"JMdict created: ([0-9-]+)", header)
    if created is None:
        raise ValueError("Official dictionary creation date is missing")
    catalog["dictionary"] = {
        "name": "JMdict", "date": created.group(1), "source": "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz",
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "license": "CC-BY-SA-4.0",
        "mimeticEntries": total, "importedForms": len(imported),
        "automaticForms": sum(e["recognition"] for e in imported),
        "changes": "Mimetic kana readings and glosses extracted; kana variants generated; curated spellings take precedence."
    }
    catalog["entries"] = curated + imported
    entries = catalog.pop("entries")
    encoded = json.dumps(catalog, ensure_ascii=False, indent=2).rstrip()[:-1]
    encoded = encoded.rstrip() + ',\n  "entries": [\n'
    encoded += ",\n".join("    " + json.dumps(e, ensure_ascii=False, separators=(",", ":")) for e in entries)
    encoded += "\n  ]\n}\n"
    json.loads(encoded)
    temporary = catalog_path.with_suffix(".json.tmp")
    temporary.write_text(encoded)
    temporary.replace(catalog_path)
    print(json.dumps({**catalog["dictionary"], "bytes": len(encoded.encode())}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("catalog", type=Path)
    arguments = parser.parse_args()
    update(arguments.source, arguments.catalog)
