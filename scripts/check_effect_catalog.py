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


def run():
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
