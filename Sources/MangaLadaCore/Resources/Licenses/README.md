# JMdict 효과음 데이터

`sound-effect-lexicon.json` contains Japanese readings and English glosses derived from JMdict, copyright James William Breen and the Electronic Dictionary Research and Development Group (EDRDG).

Source: https://www.edrdg.org/pub/Nihongo/JMdict_e.gz

Project documentation: https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project

License statement: https://www.edrdg.org/edrdg/licence.html

The dictionary subset, kana variants and curated additions are distributed under Creative Commons Attribution-ShareAlike 4.0. The EDRDG license statement and full CC BY-SA 4.0 license are included alongside this file. EDRDG does not endorse this application.

Changes: extracted entries tagged as onomatopoeic or mimetic, retained kana readings and meaning alternatives, generated hiragana/katakana variants, restricted automatic recognition of ambiguous adverbs, and added curated comic spellings and Korean preferences. The catalog records the source date, download checksum and entry IDs. Meanings are context hints rather than guaranteed Korean translations.

For each release, download the current official `JMdict_e.gz` to a temporary work directory and run `scripts/update_effect_lexicon.py <download.gz> Sources/MangaLadaCore/Resources/sound-effect-lexicon.json`, followed by the catalog, OCR-kind and Core checks. This procedure preserves curated entries and updates imported entries deterministically. The full dictionary is not bundled in the app.
