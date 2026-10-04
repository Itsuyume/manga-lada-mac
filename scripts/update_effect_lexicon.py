#!/usr/bin/env python3
"""Import a downloaded official JMdict_e.gz into the runtime effect catalog.

Download: https://www.edrdg.org/pub/Nihongo/JMdict_e.gz
Run before releases to refresh dictionary data. No network access or model calls.
Curated entries without jmdictIDs, or with a Korean default, win and are preserved.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
from typing import TypedDict
import unicodedata
import xml.etree.ElementTree as ET


class ImportedForm(TypedDict):
    glosses: list[str]
    ids: list[int]
    recognition: bool


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


def mimetic_senses(senses: list[ET.Element]) -> list[ET.Element]:
    return [s for s in senses if any(m.text == "onomatopoeic or mimetic word" for m in s.findall("misc"))]


def merge_reading(reading: ET.Element, senses: list[ET.Element], entry_id: int,
                  reserved: set[str], by_form: dict[str, ImportedForm]) -> None:
    word = reading.findtext("reb", "")
    applicable = [s for s in senses if not s.findall("stagr") or word in [r.text for r in s.findall("stagr")]]
    if not applicable:
        return
    mimetic = mimetic_senses(applicable)
    glosses = list(dict.fromkeys(g.text for s in mimetic for g in s.findall("gloss") if g.text))
    if mimetic and not glosses:
        raise ValueError("Mimetic reading has no English gloss: " + str(entry_id) + " / " + word)
    for form in sorted(kana_forms(word) - reserved):
        value = by_form.setdefault(form, {"glosses": [], "ids": [], "recognition": True})
        value["glosses"] += [g for g in glosses if g not in value["glosses"]]
        if mimetic:
            value["ids"].append(entry_id)
        # A generated kana variant can collide with an ordinary reading.
        # Retain that ambiguity even when it contributes no effect meaning.
        value["recognition"] &= bool(mimetic) and len(mimetic) == len(applicable) and automatic_form(form, applicable)


def import_entries(source, reserved):
    by_form: dict[str, ImportedForm] = {}
    total = 0
    with gzip.open(source, "rb") as stream:
        for _, entry in ET.iterparse(stream, events=("end",)):
            if entry.tag != "entry":
                continue
            senses = entry.findall("sense")
            if not mimetic_senses(senses):
                entry.clear()
                continue
            total += 1
            entry_id = int(entry.findtext("ent_seq"))
            for reading in entry.findall("r_ele"):
                merge_reading(reading, senses, entry_id, reserved, by_form)
            entry.clear()
    entries = []
    for form, value in sorted(by_form.items()):
        if not value["glosses"]:
            continue
        # Keep alternatives; this is not a one-meaning Korean replacement table.
        hint = "; ".join(value["glosses"][:12])
        if len(hint) > 600:
            hint = hint[:597].rsplit("; ", 1)[0] + "..."
        entries.append({"sources": [form], "meaning": hint, "recognition": value["recognition"],
                        "jmdictIDs": sorted(set(value["ids"]))})
    if not entries:
        raise ValueError("Dictionary contains no usable mimetic readings")
    return entries, total


def update(source, catalog_path):
    catalog = json.loads(catalog_path.read_text())
    if catalog.get("version") != 1:
        raise ValueError("Unsupported catalog version")
    curated = [entry for entry in catalog["entries"] if "jmdictIDs" not in entry or "korean" in entry]
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
        "changes": "Mimetic kana readings and glosses extracted with reading-specific sense restrictions; kana variants generated; curated spellings take precedence."
    }
    catalog["entries"] = curated + imported
    compact = {key: catalog[key] for key in ["reviewGroups", "entries"] if key in catalog}
    encoded = json.dumps({key: value for key, value in catalog.items() if key not in compact},
                         ensure_ascii=False, indent=2).rstrip()[:-1].rstrip()
    for key, entries in compact.items():
        encoded += ',\n  "' + key + '": [\n'
        encoded += ",\n".join("    " + json.dumps(e, ensure_ascii=False, separators=(",", ":")) for e in entries)
        encoded += "\n  ]"
    encoded += "\n}\n"
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
