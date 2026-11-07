#!/usr/bin/env python3
"""Split a Swift file at top-level types so it fits the company 500-line guard.

Company guards reject a new file over 500 lines. This packs whole top-level
types into sibling files. It refuses to cut inside a type: extract that piece
by hand, then run again. A split that would leave an XCTestCase extension in
another file rehomes that extension onto an independent superclass instead.
It does not edit the Xcode project.
"""
import re
from pathlib import Path

LIMIT = 500
TYPE_RE = re.compile(
    r"^(?:(?:public|open|internal|fileprivate|private|final|nonisolated)\s+)*"
    r"(?:struct|enum|class|actor|extension|protocol)\s+(\w+)",
)


def line_count(text):
    return len(text.splitlines())


def top_level_braces(text):
    """Return inclusive [open, close] indexes of every top-level brace pair."""
    spans = []
    i, n, depth, start = 0, len(text), 0, None
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if c == "#":
            hashes = 0
            j = i
            while j < n and text[j] == "#":
                hashes += 1
                j += 1
            if j < n and text[j] == '"':
                if text.startswith('"""', j):
                    closer = '"""' + ("#" * hashes)
                    end = text.find(closer, j + 3)
                else:
                    closer = '"' + ("#" * hashes)
                    end = text.find(closer, j + 1)
                i = n if end < 0 else end + len(closer)
                continue
        if c == '"':
            if text.startswith('"""', i):
                end = text.find('"""', i + 3)
                i = n if end < 0 else end + 3
                continue
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] in {'"', "\n"}:
                    i += 1
                    break
                i += 1
            continue
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                spans.append((start, i))
                start = None
            if depth < 0:
                raise ValueError("unbalanced braces")
        i += 1
    if depth != 0:
        raise ValueError("unbalanced braces")
    return spans




def declaration_chunks(text):
    """Return (header, [declaration chunks]) covering the file exactly once."""
    lines = text.splitlines(keepends=True)
    spans = top_level_braces(text)
    if not spans:
        raise ValueError("no top-level Swift type to split")
    keyword_lines = []
    for open_at, _close_at in spans:
        line_no = text.count("\n", 0, open_at)
        while line_no > 0 and not TYPE_RE.match(lines[line_no].strip()):
            line_no -= 1
        if not TYPE_RE.match(lines[line_no].strip()):
            raise ValueError("top-level brace is not a type declaration")
        keyword_lines.append(line_no)
    starts = []
    for keyword in keyword_lines:
        start = keyword
        while start > 0:
            prev = lines[start - 1].strip()
            if prev.startswith(("///", "//", "@")):
                start -= 1
                continue
            if prev == "":
                before = lines[start - 2].strip() if start >= 2 else ""
                if before.startswith(("///", "//", "@")):
                    start -= 1
                    continue
                start -= 1
                break
            break
        starts.append(start)
    chunks = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(lines)
        chunks.append("".join(lines[start:end]))
    return "".join(lines[: starts[0]]), chunks


def _type_name(chunk):
    for line in chunk.splitlines():
        match = TYPE_RE.match(line.strip())
        if match:
            return match.group(1)
    raise ValueError("split chunk has no top-level type name")






_PROPERTY = re.compile(
    r"^[ \t]*(?:(?:public|open|internal|fileprivate|private|static|class|final|lazy)[ \t]+)*"
    r"(?:let|var)[ \t]+([A-Za-z_]\w*)\b"
)
_SUITE_CLASS = re.compile(
    r"(?m)^[ \t]*(?:final[ \t]+)?class[ \t]+(\w+)[ \t]*:[ \t]*(?:XCTest\.)?XCTestCase\b"
)
_EXTENSION_LINE = re.compile(r"(?m)^[ \t]*extension[ \t]+(\w+)\b")


def fixture_case_name(suite_name):
    """Independent superclass name for helpers that must leave a suite file."""
    if suite_name.endswith("Tests") and len(suite_name) > len("Tests"):
        return suite_name[: -len("Tests")] + "FixtureCase"
    return suite_name + "FixtureCase"


def _declaration_at(text, open_at):
    line_start = text.rfind("\n", 0, open_at) + 1
    return text[line_start:open_at]


def _suite_brace(text, name):
    pattern = re.compile(
        r"\bclass\s+" + re.escape(name) + r"\s*:\s*(?:XCTest\.)?XCTestCase\b"
    )
    for open_at, close_at in top_level_braces(text):
        if pattern.search(_declaration_at(text, open_at)):
            return open_at, close_at
    return None


def _extension_brace(text):
    for open_at, close_at in top_level_braces(text):
        match = re.search(r"\bextension\s+(\w+)\s*$", _declaration_at(text, open_at))
        if match:
            return match.group(1), open_at, close_at
    return None


def _leading_properties(text, open_at):
    found = []
    for line in text[open_at + 1 :].splitlines(keepends=True):
        stripped = line.strip()
        if stripped == "" or stripped.startswith(("//", "///")):
            continue
        match = _PROPERTY.match(line)
        if not match:
            break
        found.append((match.group(1), line))
    return found


def _widen_property(line):
    """A superclass in another file cannot keep file-private stored state."""
    return re.sub(r"\b(?:private|fileprivate)[ \t]+", "", line, count=1)


def _rehome(suite_text, extension_text, name, ext_open, ext_close):
    suite_brace = _suite_brace(suite_text, name)
    if suite_brace is None:
        raise ValueError(name + " is not an XCTestCase in the suite file")
    same_file = suite_text == extension_text
    ext_body = extension_text[ext_open + 1 : ext_close]
    movable = [
        (prop, line)
        for prop, line in _leading_properties(suite_text, suite_brace[0])
        if re.search(r"\b" + re.escape(prop) + r"\b", ext_body)
    ]
    case_name = fixture_case_name(name)
    new_suite = suite_text
    for _prop, line in movable:
        new_suite = new_suite.replace(line, "", 1)
    new_suite = re.sub(
        r"(\bclass\s+" + re.escape(name) + r"\s*:\s*)(?:XCTest\.)?XCTestCase\b",
        r"\1" + case_name,
        new_suite,
        count=1,
    )
    prop_block = "".join(_widen_property(line) for _prop, line in movable)
    if same_file:
        new_suite = new_suite.replace(
            "extension " + name + " {",
            "class " + case_name + ": XCTestCase {",
            1,
        )
        needle = "class " + case_name + ": XCTestCase {"
        brace = new_suite.find(needle)
        if brace < 0:
            raise ValueError("rehome lost the fixture case declaration")
        insert_at = new_suite.find("{", brace) + 1
        if new_suite[insert_at : insert_at + 1] == "\n":
            insert_at += 1
        return new_suite[:insert_at] + prop_block + new_suite[insert_at:], new_suite
    new_ext = extension_text.replace(
        "extension " + name + " {",
        "class " + case_name + ": XCTestCase {",
        1,
    )
    needle = "class " + case_name + ": XCTestCase {"
    brace = new_ext.find(needle)
    if brace < 0:
        raise ValueError("rehome lost the fixture case declaration")
    insert_at = new_ext.find("{", brace) + 1
    if new_ext[insert_at : insert_at + 1] == "\n":
        insert_at += 1
    new_ext = new_ext[:insert_at] + prop_block + new_ext[insert_at:]
    return new_suite, new_ext


def rehome_suite_extension(suite_text, extension_text):
    """Move a cross-file XCTestCase extension onto an independent superclass."""
    found = _extension_brace(extension_text)
    if found is None:
        raise ValueError("companion file has no XCTestCase extension to rehome")
    name, ext_open, ext_close = found
    return _rehome(suite_text, extension_text, name, ext_open, ext_close)


def rehome_extensions_in_source(text):
    """Rehome a same-file XCTestCase extension before a split can strand it."""
    found = _extension_brace(text)
    if found is None:
        return text
    name, ext_open, ext_close = found
    if _suite_brace(text, name) is None:
        return text
    rewritten, _same = _rehome(text, text, name, ext_open, ext_close)
    return rewritten


def stranded_suite_extensions(bodies):
    """Names of XCTestCase extensions that landed outside their suite file."""
    suites = {}
    extensions = []
    for index, body in enumerate(bodies):
        for match in _SUITE_CLASS.finditer(body):
            suites[match.group(1)] = index
        for match in _EXTENSION_LINE.finditer(body):
            extensions.append((index, match.group(1)))
    return [
        name
        for index, name in extensions
        if name in suites and suites[name] != index
    ]



def source_lines(text):
    return len(text.split("\n")) - (1 if text.endswith("\n") else 0)


def _import_header(header):
    imports = [line for line in header.splitlines(keepends=True) if line.startswith("import ")]
    if not imports:
        return ""
    text = "".join(imports)
    return text if text.endswith("\n\n") else text + ("\n" if text.endswith("\n") else "\n\n")


def _pack(header, chunks, limit):
    files = []
    current = header
    held = 0
    extra = _import_header(header)
    for chunk in chunks:
        candidate = current + chunk
        if source_lines(candidate) <= limit:
            current = candidate
            held += 1
            continue
        if held == 0:
            raise ValueError(_type_name(chunk) + " is over " + str(limit) + " lines; extract part of that type by hand")
        files.append(current if current.endswith("\n") else current + "\n")
        current = extra + chunk.lstrip("\n")
        held = 1
        if source_lines(current) > limit:
            raise ValueError(_type_name(chunk) + " is over " + str(limit) + " lines; extract part of that type by hand")
    files.append(current if current.endswith("\n") else current + "\n")
    return files


def _split_namesake(text, source_name, limit=LIMIT):
    """Keep the file-stem type in the original file. Pack the other types beside it."""
    if source_lines(text) <= limit:
        return [(source_name, text if text.endswith("\n") else text + "\n")]
    header, chunks = declaration_chunks(text)
    stem = Path(source_name).stem
    namesake_at = next((i for i, chunk in enumerate(chunks) if _type_name(chunk) == stem), None)
    if namesake_at is None:
        bodies = _pack(header, chunks, limit)
        names = [source_name]
        for body in bodies[1:]:
            names.append(str(Path(source_name).with_name(_type_name(body) + ".swift")))
        return list(zip(names, bodies))
    before = chunks[:namesake_at]
    namesake = [chunks[namesake_at]]
    after = chunks[namesake_at + 1 :]
    kept = _pack(header, namesake, limit)
    if len(kept) != 1:
        raise ValueError(stem + " is over " + str(limit) + " lines")
    body = kept[0]
    for chunk in after:
        if source_lines(body + chunk) > limit:
            before.append(chunk)
            continue
        body += chunk
    bodies = _pack(_import_header(header) or header, before, limit) if before else []
    paths = []
    for part in bodies:
        name = str(Path(source_name).with_name(_type_name(part) + ".swift"))
        paths.append((name, part))
    paths.insert(0, (source_name, body))
    return paths



def split_namesake(text, source_name, limit=LIMIT):
    parts = _split_namesake(text, source_name, limit)
    if stranded_suite_extensions([body for _name, body in parts]):
        text = rehome_extensions_in_source(text)
        parts = _split_namesake(text, source_name, limit)
    if stranded_suite_extensions([body for _name, body in parts]):
        raise ValueError("split would leave a cross-file XCTestCase extension")
    names = [name for name, _body in parts]
    if len(names) != len(set(names)):
        raise ValueError("split would overwrite " + source_name)
    return parts


def pack(text, limit=LIMIT):
    """Pack intact types, moving stranded XCTest helpers to a fixture superclass."""
    if line_count(text) <= limit:
        return [text]
    bodies = _pack(*declaration_chunks(text), limit)
    if stranded_suite_extensions(bodies):
        bodies = _pack(*declaration_chunks(rehome_extensions_in_source(text)), limit)
    if stranded_suite_extensions(bodies):
        raise ValueError("split would leave a cross-file XCTestCase extension")
    return bodies

def apply_split(source, limit=LIMIT, dry_run=False):
    source = Path(source)
    parts = split_namesake(source.read_text(), source.name, limit)
    if len(parts) == 1:
        return [source]
    written = [source.parent / name for name, _body in parts]
    for path in written[1:]:
        if path.exists():
            raise ValueError("refusing to overwrite " + str(path))
    if dry_run:
        return written
    for path, (_name, body) in zip(written, parts):
        path.write_text(body)
    return written


def apply_rehome(suite, companion):
    suite = Path(suite)
    companion = Path(companion)
    suite_text, companion_text = rehome_suite_extension(suite.read_text(), companion.read_text())
    suite.write_text(suite_text)
    companion.write_text(companion_text)
    return suite, companion
