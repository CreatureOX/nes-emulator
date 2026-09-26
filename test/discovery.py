"""
Find test ROMs in the nes-test-roms submodule and harvest whatever evidence
we can about their expected outcome.

Pure library: it answers "what ROMs exist, and what should each one do?" and
knows nothing about configurations or running. test/suite.py builds the suite
on top of scan().

This is the ONE place that walks the submodule. Every lookup goes through
iter_rom_paths(), so no caller globs for ROMs itself.

Three independent evidence sources feed the expectation, in descending order
of trustworthiness:

  1. readme suite-level hardware assertion
     A small number of suites state that the ROMs were verified on real
     hardware, e.g. "They have been tested on an actual NES and all give a
     passing result." This is the strongest evidence available and yields
     basis="hardware" -> expected pass, but still *unconfirmed locally*.

  2. nes-test-roms/test_roms.xml
     A structured NESICIDE manifest with per-ROM `runframes`, used for the
     per-ROM frame budget -- far cheaper than the blanket default (60 frames
     vs 1200, measured ~17x faster). Its `testresult` is deliberately NOT
     used as an expectation: it records what *other emulators* do, and
     trusting it is exactly how ppu_vbl_nmi/10-even_odd_timing came to be
     mislabelled as expected=fail.

  3. nothing
     Most ROMs carry no usable expectation. They default to
     expected="pass" with basis="assumed".

`basis` is ONLY emitted when the expectation is unconfirmed. An entry with
no `basis` is authoritative and gates the run. Removing `basis` by hand after
confirming a ROM passes is the intended promotion workflow -- there is no
automated write-back, deliberately: auto-recording a FAIL would cement the
bug as an expectation.

ROMs are excluded (never run) when they are: PAL (this emulator has no PAL
timing at all), inside a demo directory such as other/, on a mapper we have
not implemented, or carrying no evidence of being a self-reporting test.
"""
import os
import re
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUBMODULE = os.path.join(ROOT, "nes-test-roms")
XML_PATH = os.path.join(SUBMODULE, "test_roms.xml")

# Mappers implemented in nes/mapper/mapper_factory.pyx.
SUPPORTED_MAPPERS = {0, 1, 2, 3, 4, 66}

# Directories holding demo/homebrew ROMs rather than tests.
EXCLUDE_DIRS = {"other", "dpcmletterbox"}

# Never descended into while walking the submodule: build inputs, not ROMs.
SKIP_DIRS = (".git", "source", "obj", "src", "tools", "tilesets")

# Word-boundary match on path components. Must NOT match "full_palette"
# or "palette_ram.nes" -- those are legitimate NTSC tests.
PAL_PATH_RE = re.compile(r"(?:^|[_\-/])pal(?:[_\-./]|$)", re.IGNORECASE)
# "... on a PAL NES", "PAL NES APU Tests"
PAL_TEXT_RE = re.compile(r"\bPAL\s+NES\b", re.IGNORECASE)

# Suite-level real-hardware assertion. The phrasing varies slightly between
# suites but always contains "all ... give ... passing result".
HW_ASSERT_RE = re.compile(
    r"all\s+(?:of\s+them\s+)?(?:give|pass(?:es)?|should\s+pass)\s+"
    r"(?:a\s+)?passing\s+result",
    re.IGNORECASE,
)

README_NAMES = ("readme.txt", "README.txt", "readme.md", "README.md")


def iter_rom_paths():
    """Yield every submodule-relative .nes path, unclassified and unfiltered.

    The ONE walk of the submodule. scan() classifies what this yields.
    """
    if not os.path.isdir(SUBMODULE):
        return
    for dirpath, dirnames, filenames in os.walk(SUBMODULE):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.lower().endswith(".nes"):
                continue
            full = os.path.join(dirpath, fn)
            yield os.path.relpath(full, SUBMODULE).replace(os.sep, "/")


_ROM_INDEX = None


def rom_index():
    """{id: submodule-relative path} for every ROM, built once and cached.

    This is what makes `id` sufficient as the only key in regression.toml:
    the path is a lookup here, not a second stored field.
    """
    global _ROM_INDEX
    if _ROM_INDEX is None:
        _ROM_INDEX = {os.path.splitext(rel)[0]: rel for rel in iter_rom_paths()}
    return _ROM_INDEX


def path_of(rom_id):
    """Repo-relative path of *rom_id*, or None when no ROM has that id.

    Deliberately NOT `rom_id + ".nes"`: 27 submodule ROMs carry an uppercase
    .NES extension (soundtest/SNDTEST.NES, stress/NEStress.NES, ...), so
    string concat only resolves on a case-insensitive filesystem and would
    turn those tests into MISSING on a Linux CI runner.
    """
    rel = rom_index().get(rom_id)
    return None if rel is None else "nes-test-roms/" + rel


def mapper_of(path):
    """Return the iNES mapper number, or None if the header is unusable."""
    try:
        with open(path, "rb") as f:
            h = f.read(16)
    except OSError:
        return None
    if len(h) < 16 or h[:4] != b"NES\x1a":
        return None
    return (h[7] & 0xF0) | (h[6] >> 4)


def load_xml():
    """Return {submodule-relative path: {"frames"}} from test_roms.xml."""
    out = {}
    if not os.path.exists(XML_PATH):
        return out
    try:
        root = ET.parse(XML_PATH).getroot()
    except ET.ParseError:
        return out
    for e in root:
        fn = (e.get("filename") or "").replace("\\", "/")
        if not fn:
            continue
        try:
            frames = int(e.get("runframes") or 0)
        except ValueError:
            frames = 0
        out[fn] = {"frames": frames}
    return out


def find_readmes(rel_dir):
    """Readme candidates for a ROM directory: same level, then parents.

    Deliberately does NOT look inside `source/`: those readme files document
    how to rebuild the ROM with ca65/ld65 and carry no expectation data.
    """
    found = []
    d = os.path.join(SUBMODULE, rel_dir)
    for _ in range(3):
        for name in README_NAMES:
            p = os.path.join(d, name)
            if os.path.exists(p):
                found.append(p)
        parent = os.path.dirname(d)
        if parent == d or not parent.startswith(SUBMODULE):
            break
        d = parent
    return found


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def classify(rel_path, xml_index):
    """Build one discovery record for a submodule-relative ROM path.

    Returns a dict with id/path plus either `excluded` (and `reason`) or the
    expectation fields.
    """
    full = os.path.join(SUBMODULE, rel_path)
    rel_dir = os.path.dirname(rel_path)
    top_dir = rel_path.split("/")[0]
    stem = os.path.splitext(rel_path)[0]

    rec = {
        "id": stem,
        "path": "nes-test-roms/" + rel_path,
    }

    # --- exclusions -----------------------------------------------------
    if top_dir in EXCLUDE_DIRS:
        rec["excluded"] = True
        rec["reason"] = "demo"
        return rec

    readmes = find_readmes(rel_dir)
    blob = "\n".join(read_text(p) for p in readmes)
    # Only the title line counts for the text rule. Matching the whole file
    # produces false positives: cpu_timing_test6 mentions "a PAL NES due to
    # the differing refresh rate" mid-sentence but is an NTSC test.
    title = ""
    for line in blob.splitlines():
        if line.strip():
            title = line.strip()
            break

    # PAL must be adjudicated BEFORE the hardware assertion: pal_apu_tests
    # carries both, and trusting its assertion would gate 10 PAL ROMs that
    # this emulator cannot possibly pass.
    if PAL_PATH_RE.search(rel_path) or PAL_TEXT_RE.search(title):
        rec["excluded"] = True
        rec["reason"] = "pal"
        return rec

    mapper = mapper_of(full)
    if mapper is None:
        rec["excluded"] = True
        rec["reason"] = "bad-header"
        return rec
    if mapper not in SUPPORTED_MAPPERS:
        rec["excluded"] = True
        rec["reason"] = "mapper-%d" % mapper
        return rec

    meta = xml_index.get(rel_path)
    if meta is None and not readmes:
        # No manifest entry and no documentation: no evidence this ROM
        # self-reports a verdict, so the blargg detector would see nothing.
        rec["excluded"] = True
        rec["reason"] = "no-detector"
        return rec

    # --- expectation ----------------------------------------------------
    rec["excluded"] = False
    if HW_ASSERT_RE.search(blob):
        rec["expected"] = "pass"
        rec["basis"] = "hardware"
    else:
        rec["expected"] = "pass"
        rec["basis"] = "assumed"

    if meta and meta["frames"] > 0:
        rec["frames"] = meta["frames"]
    rec["mapper"] = mapper
    return rec


def scan():
    """Classify every ROM in the submodule. Returns a list sorted by id."""
    xml_index = load_xml()
    out = [classify(rel, xml_index) for rel in iter_rom_paths()]
    out.sort(key=lambda r: r["id"])
    return out
