#!/usr/bin/env python3
"""Split oversized Swift and keep company size-500 plus Swift call shape green.

Company guards reject a new file over 500 lines and any growth of a baselined
file. Xcode 26 rejects a call whose explicit labels are not in declaration
order, and a method reference whose defaulted parameters widen the function
type. This packs whole top-level Swift types, keeps the namesake type in the
original file, and checks those gates. It does not edit the Xcode project.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

from split_swift_types import (
    apply_rehome, apply_split, line_count, pack, rehome_suite_extension,
    source_lines, split_namesake, stranded_suite_extensions,
    _import_header, _type_name, declaration_chunks, top_level_braces,
)

LIMIT = 500
CODE = re.compile(r"\.(ts|tsx|js|jsx|mjs|cjs|py|swift|ex|exs|sh|rb|go|rs)$")
SKIP = re.compile(r"(^|/)(node_modules|vendor|dist|build|\.next|Pods)/|\.gen\.|\.generated\.|\.min\.|\.d\.ts$|lock")
FUNC_RE = re.compile(r"\bfunc\s+([A-Za-z_]\w*)\s*(?:<[^>(]*)>\s*\(|\bfunc\s+([A-Za-z_]\w*)\s*\(")
CALL_RE = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\s*\(")
LABEL_RE = re.compile(r"(?:([A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:")
TYPE_NAME_RE = re.compile(r"\b(?:struct|enum|class|actor|extension)\s+([A-Za-z_]\w*)")
STATIC_FUNC_RE = re.compile(r"\bstatic\s+func\s+([A-Za-z_]\w*)\s*(?:<[^>(]*)?\s*\(")
DEFAULT_REF_RE = re.compile(
    r"\.(?:map|compactMap|flatMap|filter|forEach|sorted|reduce|contains|allSatisfy|first)\(\s*"
    r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\s*\)"
)


def extract_declarations(text, names, owner=None, internalize=()):
    """Move whole types or computed members; never widen access implicitly."""
    if not names or len(set(names)) != len(names):
        raise ValueError("declaration names must be unique")
    if len(set(internalize)) != len(internalize) or not set(internalize) <= set(names) or (owner and internalize):
        raise ValueError("internalize requires unique extracted top-level type names")
    if owner is None:
        header, chunks = declaration_chunks(text)
        moved = [chunk for chunk in chunks if _type_name(chunk) in names]
        if len(moved) != len(names):
            raise ValueError("missing or ambiguous type declaration")
        output = []
        for chunk in moved:
            name = _type_name(chunk)
            declaration = re.search(
                r"(?m)^(?P<modifiers>(?:(?:public|open|internal|fileprivate|private|final|nonisolated)[ \t]+)*)"
                r"(?:struct|enum|class|actor|extension|protocol)[ \t]+" + re.escape(name) + r"\b", chunk,
            )
            modifiers = declaration["modifiers"]
            restricted = re.search(r"\b(private|fileprivate)\b", modifiers)
            if restricted and name not in internalize:
                raise ValueError("review type access before extraction: " + name)
            if name in internalize:
                if not restricted:
                    raise ValueError("type is already accessible across files: " + name)
                # Only the reviewed type declaration changes; member access stays intact.
                start, end = declaration.span("modifiers")
                chunk = chunk[:start] + re.sub(r"\b(?:private|fileprivate)[ \t]+", "", modifiers) + chunk[end:]
            output.append(chunk)
        return (header + "".join(c for c in chunks if c not in moved)).rstrip() + "\n", (_import_header(header) + "".join(output).lstrip("\n")).rstrip() + "\n"
    pattern = r"(?m)^(?:(?:public|internal|final) +)*(?:struct|class|enum|actor|extension) +" + re.escape(owner) + r"\b[^\n{]*\{"
    owners = list(re.finditer(pattern, text))
    if not owners:
        raise ValueError("missing owner")
    declaration = owners[0]
    end = next(b for a, b in top_level_braces(text) if a == declaration.end() - 1)
    chunk = text[declaration.start():end + 1]
    opening, closing = top_level_braces(chunk)[0]
    body = chunk[opening + 1:closing]
    spans = top_level_braces(body)
    ranges = []
    for name in names:
        pattern = r"(?m)^    (?:(?:public|internal|private|fileprivate|static|mutating) +)*(?:func|var) +" + re.escape(name) + r"\b"
        matches = list(re.finditer(pattern, body))
        if len(matches) != 1:
            raise ValueError("missing or ambiguous member: " + name)
        match = matches[0]
        if re.search(r"\b(private|fileprivate)\b", match[0]):
            raise ValueError("review member access before extraction: " + name)
        start = match.start()
        while start > 0:
            previous = body.rfind("\n", 0, start - 1) + 1
            if not body[previous:start].strip().startswith(("//", "@")):
                break
            start = previous
        block = next(((a, b) for a, b in spans if a >= match.end()), None)
        if block is None or not re.fullmatch(r"[^{}]*", body[match.end():block[0]]):
            raise ValueError("member has no complete body: " + name)
        signature = body[match.end():block[0]]
        if ("var " in match[0] and "=" in signature) or re.search(r"(?m)^    (?:func|var|let)\b", signature):
            raise ValueError("member is not computed: " + name)
        ranges.append((start, block[1] + 1))
    ranges.sort()
    if any(end > next_start for (_, end), (next_start, _) in zip(ranges, ranges[1:])):
        raise ValueError("overlapping members")
    moved = "\n\n".join(body[a:b] for a, b in ranges)
    for a, b in reversed(ranges):
        body = body[:a].rstrip("\n") + "\n\n" + body[b:].lstrip("\n")
    kept = text.replace(chunk, chunk[:opening + 1] + body + chunk[closing:], 1)
    return kept, _import_header(text) + "extension " + owner + " {\n" + moved + "\n}\n"


def relocate_prefix(text, marker, sibling):
    """Move the prefix before marker into a sibling module and re-export it."""
    lines = text.splitlines(keepends=True)
    index = next((i for i, line in enumerate(lines) if line.startswith(marker)), None)
    if index is None:
        raise ValueError("marker not found: " + marker)
    prefix = "".join(lines[:index])
    prefix = re.sub(r"(?m)^(function )\b", r"export \1", prefix)
    if not prefix.endswith("\n"):
        prefix += "\n"
    tail = "".join(lines[index:])
    names = re.findall(r"(?m)^export (?:async )?(?:function|const|class|type|interface|enum) (\w+)", prefix)
    if not names:
        raise ValueError("prefix has no exports")
    spec = "./" + Path(sibling).stem
    original = (
        "export * from '" + spec + "';\nimport {\n"
        + "".join("  " + name + ",\n" for name in names)
        + "} from '" + spec + "';\n\n"
        + tail
    )
    return prefix, original if original.endswith("\n") else original + "\n"


def _signature_end(text, open_at):
    depth = 0
    i = open_at
    while i < len(text):
        c = text[i]
        if c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i = text.find("\n", i)
            if i < 0:
                return len(text)
            continue
        if c == '"':
            i += 1
            while i < len(text) and text[i] not in {'"', "\n"}:
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def _top_level_pieces(body):
    parts = []
    start = 0
    depth = 0
    i = 0
    while i < len(body):
        c = body[i]
        if c == '"':
            i += 1
            while i < len(body) and body[i] not in {'"', "\n"}:
                i += 2 if body[i] == "\\" else 1
        elif c in "([{<":
            depth += 1
        elif c in ")]}>":
            depth = max(0, depth - 1)
        elif c == "," and depth == 0:
            parts.append(body[start:i])
            start = i + 1
        i += 1
    parts.append(body[start:])
    return parts


def _external_label(piece):
    match = LABEL_RE.search(piece.strip())
    if not match:
        return None
    external = match.group(1) or match.group(2)
    return None if external == "_" else external


def declared_labels(text):
    labels = {}
    for match in FUNC_RE.finditer(text):
        name = match.group(1) or match.group(2)
        end = _signature_end(text, match.end() - 1)
        found = [label for piece in _top_level_pieces(text[match.end() : end]) if (label := _external_label(piece))]
        labels.setdefault(name, found)
    return labels


def defaulted_static_methods(text):
    """Static methods whose signature includes a defaulted parameter."""
    owners = [(match.start(), match.group(1)) for match in TYPE_NAME_RE.finditer(text)]
    found = set()
    for match in STATIC_FUNC_RE.finditer(text):
        end = _signature_end(text, match.end() - 1)
        if "=" not in text[match.end() : end]:
            continue
        prior = [name for pos, name in owners if pos < match.start()]
        if prior:
            found.add((prior[-1], match.group(1)))
    return found


def unapplied_default_references(text, methods):
    """Higher-order calls that pass a defaulted method instead of calling it.

    Xcode types `key(_:calendar:)` as `(Date, Calendar) -> String`, so
    `dates.map(PersonalBodyDay.key)` does not match `(Date) -> String`.
    """
    violations = []
    for match in DEFAULT_REF_RE.finditer(text):
        parts = match.group(1).split(".")
        if (parts[-2], parts[-1]) not in methods:
            continue
        violations.append((text.count("\n", 0, match.start()) + 1, match.group(1)))
    return violations


def argument_order_violations(text):
    """Explicit call labels that are not in the same-file declaration order."""
    labels = declared_labels(text)
    violations = []
    for match in CALL_RE.finditer(text):
        if text[max(0, match.start() - 5) : match.start()] == "func ":
            continue
        name = match.group(1)
        expected = labels.get(name)
        if not expected:
            continue
        end = _signature_end(text, match.end() - 1)
        provided = [label for piece in _top_level_pieces(text[match.end() : end]) if (label := _external_label(piece))]
        order = [label for label in provided if label in expected]
        ranked = [expected.index(label) for label in order]
        if ranked != sorted(ranked):
            violations.append((text.count("\n", 0, match.start()) + 1, name, order))
    return violations


def measure(files, read):
    out = {}
    for name in files:
        if not CODE.search(name) or SKIP.search(name):
            continue
        text = read(name)
        if text is None:
            continue
        count = source_lines(text)
        if count > LIMIT:
            out[name] = count
    return out


def compare(current, baseline):
    fails = []
    for name, count in current.items():
        if name not in baseline:
            fails.append(name + ": " + str(count) + " lines, over " + str(LIMIT) + " and not baselined")
        elif count > baseline[name]:
            fails.append(name + ": grew " + str(baseline[name]) + " -> " + str(count))
    return fails


def check_repo(root):
    root = Path(root)
    files = subprocess.check_output(["git", "ls-files"], cwd=root, text=True).splitlines()
    current = measure(files, lambda name: (root / name).read_text(errors="replace") if (root / name).is_file() else None)
    baseline_path = root / ".company-guards" / "size-baseline.json"
    baseline = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
    fails = compare(current, baseline)
    swift = []
    methods = set()
    for name in files:
        if not name.endswith(".swift"):
            continue
        path = root / name
        if not path.is_file():
            continue
        text = path.read_text(errors="replace")
        swift.append((name, text))
        methods.update(defaulted_static_methods(text))
        for line, func, order in argument_order_violations(text):
            fails.append(name + ":" + str(line) + ": argument order for " + func + " " + ",".join(order))
    for name, text in swift:
        for line, ref in unapplied_default_references(text, methods):
            fails.append(name + ":" + str(line) + ": defaulted reference " + ref)
    return fails


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path)
    parser.add_argument("--limit", type=int, default=LIMIT)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--relocate-prefix", help="move the prefix before this exact line into --sibling")
    parser.add_argument("--sibling", type=Path)
    parser.add_argument("--rehome-extension", type=Path,
                        help="move a cross-file XCTestCase extension to an independent superclass")
    parser.add_argument("--extract", nargs="+", help="move named types or --owner computed members to --sibling")
    parser.add_argument("--owner", help="type whose computed members are extracted")
    parser.add_argument("--internalize", nargs="+", default=[],
                        help="explicitly make selected private/fileprivate extracted types internal")
    args = parser.parse_args()
    try:
        if args.extract:
            if args.source is None or args.sibling is None or args.sibling.exists():
                raise ValueError("extract needs a source and a new --sibling")
            kept, moved = extract_declarations(args.source.read_text(), args.extract, args.owner, args.internalize)
            if source_lines(moved) > args.limit:
                raise ValueError("extracted sibling exceeds limit")
            if not args.dry_run:
                args.sibling.write_text(moved)
                args.source.write_text(kept)
            print(str(args.sibling) + ": " + str(source_lines(moved)) + " lines")
            return
        if args.check:
            fails = check_repo(args.root)
            for fail in fails:
                print("size-500: " + fail)
            if fails:
                parser.exit(1, "split-size-ratchet: " + str(len(fails)) + " violation(s)\n")
            print("split-size-ratchet: clean")
            return
        if args.relocate_prefix:
            if args.source is None or args.sibling is None:
                raise ValueError("relocate-prefix needs a source and --sibling")
            prefix, original = relocate_prefix(args.source.read_text(), args.relocate_prefix, args.sibling.name)
            if source_lines(prefix) > args.limit or source_lines(original) > args.limit:
                raise ValueError("relocate still exceeds " + str(args.limit) + " lines")
            if not args.dry_run:
                args.sibling.write_text(prefix)
                args.source.write_text(original)
            print(args.sibling.name + ": " + str(source_lines(prefix)) + " lines")
            print(args.source.name + ": " + str(source_lines(original)) + " lines")
            return
        if args.rehome_extension:
            if args.source is None:
                raise ValueError("--rehome-extension needs a source")
            suite, companion = rehome_suite_extension(args.source.read_text(), args.rehome_extension.read_text())
            if not args.dry_run:
                args.source.write_text(suite)
                args.rehome_extension.write_text(companion)
            print(args.source.name + ": " + str(line_count(suite)) + " lines")
            print(args.rehome_extension.name + ": " + str(line_count(companion)) + " lines")
            return
        if args.source is None:
            raise ValueError("a Swift source or --check is required")
        if args.dry_run:
            parts = split_namesake(args.source.read_text(), args.source.name, args.limit)
            for name, body in parts:
                print(name + ": " + str(source_lines(body)) + " lines")
            return
        for path in apply_split(args.source, args.limit, False):
            print(str(path) + ": " + str(source_lines(path.read_text())) + " lines")
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        parser.exit(1, "split-size-ratchet: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
