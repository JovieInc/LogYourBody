#!/usr/bin/env python3
"""Split oversized Swift and keep company size-500 plus Swift argument order green.

Company guards reject a new file over 500 lines and any growth of a baselined
file. Xcode 26 rejects a call whose explicit labels are not in declaration
order. This packs whole top-level Swift types, keeps the namesake type in the
original file, and checks both gates. It does not edit the Xcode project.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

LIMIT = 500
CODE = re.compile(r"\.(ts|tsx|js|jsx|mjs|cjs|py|swift|ex|exs|sh|rb|go|rs)$")
SKIP = re.compile(r"(^|/)(node_modules|vendor|dist|build|\.next|Pods)/|\.gen\.|\.generated\.|\.min\.|\.d\.ts$|lock")
TYPE_RE = re.compile(
    r"^(?:(?:public|open|internal|fileprivate|private|final|nonisolated)\s+)*"
    r"(?:struct|enum|class|actor|extension|protocol)\s+(\w+)"
)
FUNC_RE = re.compile(r"\bfunc\s+([A-Za-z_]\w*)\s*(?:<[^>(]*)>\s*\(|\bfunc\s+([A-Za-z_]\w*)\s*\(")
CALL_RE = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\s*\(")
LABEL_RE = re.compile(r"(?:([A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:")


def source_lines(text):
    return len(text.split("\n")) - (1 if text.endswith("\n") else 0)


def top_level_braces(text):
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
        if c == '"':
            if text.startswith('"""', i):
                end = text.find('"""', i + 3)
                i = n if end < 0 else end + 3
                continue
            i += 1
            while i < n and text[i] not in {'"', "\n"}:
                i += 2 if text[i] == "\\" else 1
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
    lines = text.splitlines(keepends=True)
    spans = top_level_braces(text)
    if not spans:
        raise ValueError("no top-level Swift type to split")
    starts = []
    for open_at, _close_at in spans:
        line_no = text.count("\n", 0, open_at)
        while line_no > 0 and not TYPE_RE.match(lines[line_no].strip()):
            line_no -= 1
        if not TYPE_RE.match(lines[line_no].strip()):
            raise ValueError("top-level brace is not a type declaration")
        start = line_no
        while start > 0 and lines[start - 1].strip().startswith(("///", "//", "@")):
            start -= 1
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
            raise ValueError(_type_name(chunk) + " is over " + str(limit) + " lines")
        files.append(current if current.endswith("\n") else current + "\n")
        current = extra + chunk.lstrip("\n")
        held = 1
        if source_lines(current) > limit:
            raise ValueError(_type_name(chunk) + " is over " + str(limit) + " lines")
    files.append(current if current.endswith("\n") else current + "\n")
    return files


def split_namesake(text, source_name, limit=LIMIT):
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
        if len(names) != len(set(names)):
            raise ValueError("split would overwrite " + source_name)
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
        if name == source_name or name in paths:
            raise ValueError("split would overwrite " + name)
        paths.append((name, part))
    paths.insert(0, (source_name, body))
    return paths


def apply_split(source, limit=LIMIT, dry_run=False):
    source = Path(source)
    parts = split_namesake(source.read_text(), source.name, limit)
    if len(parts) == 1:
        return [source]
    written = [source.with_name(name) if not Path(name).is_absolute() else Path(name) for name, _body in parts]
    # parts store basenames from split_namesake
    written = [source.parent / name for name, _body in parts]
    for path in written[1:]:
        if path.exists():
            raise ValueError("refusing to overwrite " + str(path))
    if dry_run:
        return written
    for path, (_name, body) in zip(written, parts):
        path.write_text(body)
    return written


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
    for name in files:
        if name.endswith(".swift"):
            path = root / name
            if not path.is_file():
                continue
            for line, func, order in argument_order_violations(path.read_text(errors="replace")):
                fails.append(name + ":" + str(line) + ": argument order for " + func + " " + ",".join(order))
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
    args = parser.parse_args()
    try:
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
