#!/usr/bin/env python3
"""Real importer behavior: empty/malformed data, refresh, variants and side effects."""
from contextlib import redirect_stdout
import gzip
import io
import json
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from update_effect_lexicon import update


def check_reading_restrictions():
    xml = '''<?xml version="1.0"?>
<!-- JMdict created: 2026-10-04 -->
<JMdict>
<entry><ent_seq>10</ent_seq>
<r_ele><reb>バシャバシャ</reb></r_ele><r_ele><reb>パシャパシャ</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>splashing</gloss></sense>
<sense><stagr>パシャパシャ</stagr><misc>onomatopoeic or mimetic word</misc><gloss>camera shutter</gloss></sense></entry>
<entry><ent_seq>11</ent_seq>
<r_ele><reb>コロコロ</reb></r_ele><r_ele><reb>コロンコロン</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>rolling</gloss></sense>
<sense><stagr>コロコロ</stagr><gloss>lint roller</gloss></sense></entry>
<entry><ent_seq>12</ent_seq>
<r_ele><reb>ヌーボー</reb></r_ele><r_ele><reb>ヌーヴォー</reb></r_ele>
<sense><gloss>modern</gloss></sense>
<sense><stagr>ヌーボー</stagr><misc>onomatopoeic or mimetic word</misc><gloss>vague</gloss></sense></entry>
<entry><ent_seq>13</ent_seq>
<r_ele><reb>ドンドン</reb></r_ele><r_ele><reb>どんどん</reb></r_ele>
<sense><stagr>ドンドン</stagr><misc>onomatopoeic or mimetic word</misc><gloss>beating</gloss></sense>
<sense><stagr>どんどん</stagr><gloss>progressing</gloss></sense></entry>
<entry><ent_seq>14</ent_seq><r_ele><reb>バシャバシャ</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>sploshing</gloss></sense></entry>
</JMdict>'''
    with tempfile.TemporaryDirectory(prefix="effect-readings-") as directory:
        source, catalog = Path(directory) / "dictionary.gz", Path(directory) / "catalog.json"
        curated = {"sources": ["カチッ"], "korean": "딸깍", "jmdictIDs": [10]}
        adverb = {"sources": ["そろそろ"], "meaning": "soon", "recognition": False, "curated": True, "jmdictIDs": [1345605]}
        catalog.write_text(json.dumps({"version": 1, "entries": [curated, adverb]}))
        source.write_bytes(gzip.compress(xml.encode()))
        original = source.read_bytes()
        with redirect_stdout(io.StringIO()):
            update(source, catalog)
        data = json.loads(catalog.read_text())
        by_form = {s: e for e in data["entries"] for s in e["sources"]}
        assert by_form["バシャバシャ"]["meaning"] == "splashing; sploshing", "Camera meaning leaked to water-only reading"
        assert by_form["ばしゃばしゃ"]["meaning"] == by_form["バシャバシャ"]["meaning"]
        assert by_form["パシャパシャ"]["meaning"] == "splashing; camera shutter", "A permitted meaning was removed"
        assert by_form["バシャバシャ"]["jmdictIDs"] == [10, 14], "Reading restriction lost merged provenance"
        assert by_form["コロンコロン"]["recognition"] and not by_form["コロコロ"]["recognition"], "Other readings changed ordinary-word ambiguity"
        assert by_form["ヌーボー"]["meaning"] == "vague" and not by_form["ヌーボー"]["recognition"]
        assert "ヌーヴォー" not in by_form and "ぬーゔぉー" not in by_form, "A non-mimetic reading became an effect"
        assert not by_form["ドンドン"]["recognition"] and not by_form["どんどん"]["recognition"], "Generated kana variants lost ordinary-word ambiguity"
        assert by_form["カチッ"] == curated and source.read_bytes() == original, "Import changed curated forms or dictionary source"
        assert by_form["そろそろ"] == adverb, "Refresh lost a curated ordinary-word exclusion or its provenance"
        first = catalog.read_bytes()
        with redirect_stdout(io.StringIO()):
            update(source, catalog)
        assert catalog.read_bytes() == first, "Restricted readings changed on repeated refresh"
        for invalid_sense in [
            "<sense><misc>onomatopoeic or mimetic word</misc></sense>",
            "<sense><stagr>ドンドン</stagr><misc>onomatopoeic or mimetic word</misc><gloss>beat</gloss></sense>"
        ]:
            bad = '<!-- JMdict created: 2026-10-04 --><JMdict><entry><ent_seq>99</ent_seq><r_ele><reb>かちっ</reb></r_ele>' + invalid_sense + '</entry></JMdict>'
            source.write_bytes(gzip.compress(bad.encode()))
            try:
                update(source, catalog)
            except ValueError:
                pass
            else:
                raise AssertionError("Missing gloss or a dictionary with no applicable effect reading was accepted")
            assert catalog.read_bytes() == first, "Failed reading import overwrote the catalog"
            assert not catalog.with_suffix('.json.tmp').exists(), "Failed reading import left a partial catalog"
    print("Reading restrictions passed: scoped meanings, kana variants, ordinary words, provenance and refresh preservation")


def run():
    check_reading_restrictions()
    with tempfile.TemporaryDirectory(prefix="effect-catalog-") as directory:
        root = Path(directory)
        source, catalog = root / "dictionary.gz", root / "catalog.json"
        curated = {"sources": ["カチッ"], "korean": "딸깍"}
        review_groups = [{"sources": ["カチッ"], "options": [
            {"context": "스위치", "korean": "딸깍"}, {"context": "단단한 접촉", "korean": "딱"}]}]
        catalog.write_text(json.dumps({"version": 1, "entries": [curated], "reviewGroups": review_groups}))
        baseline = catalog.read_bytes()
        for invalid in ["", "<JMdict>", "<JMdict></JMdict>"]:
            source.write_bytes(gzip.compress(invalid.encode()))
            try:
                update(source, catalog)
            except (ValueError, ET.ParseError):
                pass
            else:
                raise AssertionError("Empty/malformed source was accepted")
            assert catalog.read_bytes() == baseline, "Failed import replaced the existing catalog"
        xml = '''<?xml version="1.0"?>
<!-- JMdict created: 2026-10-04 -->
<JMdict>
<entry><ent_seq>1</ent_seq><r_ele><reb>ねばねば</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>sticky</gloss></sense></entry>
<entry><ent_seq>2</ent_seq><r_ele><reb>きっと</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>surely</gloss></sense></entry>
<entry><ent_seq>3</ent_seq><r_ele><reb>かちっ</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>click</gloss></sense></entry>
<entry><ent_seq>4</ent_seq><r_ele><reb>ねばねば</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>gooey</gloss></sense></entry>
<entry><ent_seq>5</ent_seq><r_ele><reb>ああ</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>caw</gloss></sense></entry>
<entry><ent_seq>6</ent_seq><r_ele><reb>あっさり</reb></r_ele>
<sense><misc>onomatopoeic or mimetic word</misc><gloss>readily</gloss></sense></entry>
</JMdict>'''
        source.write_bytes(gzip.compress(xml.encode()))
        original = source.read_bytes()
        with redirect_stdout(io.StringIO()):
            update(source, catalog)
            first = catalog.read_bytes()
            update(source, catalog)
        assert catalog.read_bytes() == first and source.read_bytes() == original, "Refresh was not deterministic or changed its source"
        data = json.loads(first)
        assert data["reviewGroups"] == review_groups, "Dictionary refresh changed manually curated review options"
        by_form = {s: e for e in data["entries"] for s in e["sources"]}
        assert by_form["カチッ"] == curated, "Imported entry replaced a curated Korean form"
        assert by_form["ネバネバ"]["recognition"] and by_form["ねばねば"]["meaning"] == "sticky; gooey"
        assert by_form["ねばねば"]["jmdictIDs"] == [1, 4], "Duplicate spelling lost a meaning or provenance"
        for word in ["きっと", "ああ", "あっさり"]:
            assert not by_form[word]["recognition"], "Ordinary adverb or speech became an automatic effect"
        source.write_bytes(gzip.compress(xml.replace("gooey", "viscous").encode()))
        with redirect_stdout(io.StringIO()):
            update(source, catalog)
        assert b"viscous" in catalog.read_bytes() and b"gooey" not in catalog.read_bytes(), "Refresh retained stale imported meanings"
    print("Effect catalog checks passed: invalid/empty imports, unchanged source, variants, ambiguous speech, curated precedence, merged meanings and deterministic refresh")


if __name__ == "__main__":
    run()
