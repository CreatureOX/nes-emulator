"""Scan nes-test-roms for test ROMs and decide each one's expectation (pass).

Pure library: scan_all() walks the submodule once and discovers each ROM's expectation;
it knows nothing about configs or running. test_picker.py builds the list on
top.

A ROM is kept only when it self-reports a machine-readable verdict, so every
kept ROM is simply expected to pass. Excluded when PAL, in a demo dir, on an
unimplemented mapper, or with no verdict evidence.

Exclusions here are ROM-intrinsic -- the ROM can't be auto-judged. A second,
dir-level opt-out (DEFAULT_EXCLUDE_DIRS in launcher) is applied at run time
for suites we choose not to gate; the two layers are distinct on purpose.
"""
import os
import re
import xml.etree.ElementTree as ET

import test_judge

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUBMODULE = os.path.join(ROOT, "nes-test-roms")
XML_PATH = os.path.join(SUBMODULE, "test_roms.xml")

# Mappers implemented in nes/mapper/mapper_factory.pyx.
SUPPORTED_MAPPERS = {0, 1, 2, 3, 4, 66}

# Directories holding demo/homebrew ROMs rather than tests.
EXCLUDE_DIRS = {"other", "dpcmletterbox"}

# Directories we never run: no machine-readable self-reported verdict. Some are
# audio/visual demos with no PASS/FAIL; others need real-hardware artifacts our
# RGB emulator can't reproduce (e.g. tvpassfail's "PASS!" is NTSC-only). The
# per-dir note documents WHY and what "correct" looks like, without gating.
IGNORE_DIRS = {
    "volume_tests": "audio volume listening test; verified by ear against reference .ogg",
    "stomper": "Super Mario World stomp animation demo; no self-reported verdict",
    "soundtest": "APU sound test; verified by ear / oscilloscope; no on-screen verdict",
    "scrolltest": "scrolling render demo; judged visually, no PASS/FAIL text",
    "scanline": "mid-scanline PPU write test; right 'Errors' column must show no stray '*' (visual); no printed pass",
    "full_palette": "palette demo; judged visually; no verdict",
    "tvpassfail": "display crosstalk demo; RGB emulators show '%%%' not 'PASS!' ('PASS!' is NTSC artifact); no machine verdict",
    "spritecans-2011": "64 soda-can bounce intro (OAM cycling); no self-reported verdict",
    "vaus-test": "Vaus/Arkanoid paddle controller test; requires manual paddle input, no machine-readable verdict",
}

# Never descended into while walking the submodule: build inputs, not ROMs.
SKIP_DIRS = (".git", "source", "obj", "src", "tools", "tilesets")

# Word-boundary match on path components. Must NOT match "full_palette"
# or "palette_ram.nes" -- those are legitimate NTSC tests.
PAL_PATH_RE = re.compile(r"(?:^|[_\-/])pal(?:[_\-./]|$)", re.IGNORECASE)
# "... on a PAL NES", "PAL NES APU Tests"
PAL_TEXT_RE = re.compile(r"\bPAL\s+NES\b", re.IGNORECASE)

# Suite-level real-hardware assertion; phrasing varies but always contains
# "all ... give ... passing result".
HW_ASSERT_RE = re.compile(
    r"all\s+(?:of\s+them\s+)?(?:give|pass(?:es)?|should\s+pass)\s+"
    r"(?:a\s+)?passing\s+result",
    re.IGNORECASE,
)

README_NAMES = ("readme.txt", "README.txt", "readme.md", "README.md")


def iter_rom_paths():
    """Yield every submodule-relative .nes path, unclassified and unfiltered.

    The one walk of the submodule; scan_all() classifies what this yields.
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

    Lets `id` be the only key in launcher.toml -- the path is a lookup here,
    not a stored field.
    """
    global _ROM_INDEX
    if _ROM_INDEX is None:
        _ROM_INDEX = {os.path.splitext(rel)[0]: rel for rel in iter_rom_paths()}
    return _ROM_INDEX


def path_of(rom_id):
    """Repo-relative path of *rom_id*, or None if no ROM has that id.

    Not `rom_id + ".nes"`: 27 submodule ROMs use an uppercase .NES extension
    and would turn MISSING on a case-sensitive Linux CI runner.
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
    """Return {submodule-relative path: {"frames"}} from test_roms.xml.

    Only `runframes` (frame budget) is used; `testresult` is NOT an expectation
    -- it records what OTHER emulators do, and trusting it once mislabelled
    ppu_vbl_nmi/10-even_odd_timing as expected=fail (it passes here).
    """
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
    """Readme candidates for a ROM dir: same level, then parents.

    Skips `source/` readmes -- they document rebuilding the ROM, no verdict.
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


def discover_rom(rel_path, xml_index):
    """Build one discovery record for a submodule-relative ROM path.

    Returns a dict with id/path plus either `excluded` (and `reason`) or the
    expectation fields.
    """
    full = os.path.join(SUBMODULE, rel_path)
    rel_dir = os.path.dirname(rel_path)
    suite_dir = test_judge.top_dir(rel_path)
    stem = os.path.splitext(rel_path)[0]

    rec = {
        "id": stem,
        "path": "nes-test-roms/" + rel_path,
    }

    # --- deliberate ignores (no machine-readable self-reported verdict) ---
    if suite_dir in IGNORE_DIRS:
        rec["excluded"] = True
        rec["reason"] = "unknown-result"
        rec["ignore_note"] = IGNORE_DIRS[suite_dir]
        return rec

    # --- exclusions -----------------------------------------------------
    if suite_dir in EXCLUDE_DIRS:
        rec["excluded"] = True
        rec["reason"] = "demo"
        return rec

    readmes = find_readmes(rel_dir)
    blob = "\n".join(read_text(p) for p in readmes)
    # Only the title line: scanning the whole readme misfires (e.g.
    # cpu_timing_test6 says "a PAL NES ... refresh rate" but is NTSC).
    title = ""
    for line in blob.splitlines():
        if line.strip():
            title = line.strip()
            break

    # PAL checked before the hardware assertion: pal_apu_tests carries both,
    # and trusting its assertion would gate 10 PAL ROMs we can't pass.
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

    # Every kept ROM is expected to pass; a HW readme assertion is docs only.
    rec["excluded"] = False
    rec["expected"] = "pass"

    if meta and meta["frames"] > 0:
        rec["frames"] = meta["frames"]
    rec["mapper"] = mapper
    return rec


def scan_all():
    """Discover every ROM in the submodule. Returns a list sorted by id."""
    xml_index = load_xml()
    out = [discover_rom(rel, xml_index) for rel in iter_rom_paths()]
    out.sort(key=lambda r: r["id"])
    return out
