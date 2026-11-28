"""Additive launch-audit registration resolution used by the manifest repair loop."""
import re
import repository_docs

UNION_REFUSAL = "additive manifest union keeps every parent test input"
_HUNK = re.compile(r"^<<<<<<<[^\n]*\n(.*?\n?)=======\n(.*?\n?)>>>>>>>[^\n]*\n", re.M | re.S)
_TRIPLE = re.compile(r'\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)')
_PY_LIST = re.compile(
    r"\[item\[0\] for item in AUDIT\._AUDIT_SIBLINGS\],\s*\[(.*?)\]",
    re.S,
)
_TS_LIST = re.compile(r"for \(const input of \[(.*?)\]", re.S)


def _sibling_triples(text):
    match = re.search(r"_AUDIT_SIBLINGS = \((.*?)\n\)", text, re.S)
    triples = [tuple(item) for item in _TRIPLE.findall(match.group(1))] if match else []
    if not triples:
        raise ValueError(UNION_REFUSAL + ": missing audit siblings")
    return triples


def _union_triples(base_text, ours_text, theirs_text):
    from manifest_union import union_strings
    base, ours, theirs = (_sibling_triples(text) for text in (base_text, ours_text, theirs_text))
    by_name = {}
    for item in (*base, *ours, *theirs):
        previous = by_name.setdefault(item[0], item)
        if previous != item:
            raise ValueError(UNION_REFUSAL + ": sibling identity diverged")
    names = union_strings(
        [item[0] for item in base], [item[0] for item in ours], [item[0] for item in theirs],
    )
    return [by_name[name] for name in names]


def _render_siblings(triples):
    rows = "\n".join(
        f'    ("{name}", "{filename}", "{export}"),' for name, filename, export in triples
    )
    exports = ",\n".join(f"    {export}" for _name, _filename, export in triples)
    return (
        "_AUDIT_SIBLINGS = (\n"
        f"{rows}\n"
        ")\n(\n"
        f"{exports},\n"
        ") = [_load_sibling(*sibling) for sibling in _AUDIT_SIBLINGS]\n"
    )


def _quoted_names(text, pattern):
    match = pattern.search(text)
    if not match:
        raise ValueError(UNION_REFUSAL + ": missing sibling name list")
    inner = match.group(1)
    names = re.findall(r"""(['"])([^'"]+)\1""", inner)
    if not names and inner.strip():
        raise ValueError(UNION_REFUSAL + ": sibling name list is not quoted strings")
    quotes = {quote for quote, _name in names}
    if len(quotes) > 1:
        raise ValueError(UNION_REFUSAL + ": mixed sibling quote styles")
    return [name for _quote, name in names]


def _resolve_audit_python(working, triples):
    """Replace the sibling block and union export calls. Other hunks refuse."""
    exports = {export for _name, _filename, export in triples}
    start = working.find("_AUDIT_SIBLINGS = (")
    closer = working.find(">>>>>>>", start)
    if start < 0 or closer < 0 or "<<<<<<<" in working[:start]:
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not the sibling block")
    end = working.find("\n", closer)
    if end < 0:
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not the sibling block")
    merged = working[:start] + _render_siblings(triples) + working[end + 1:]

    def call_union(match):
        def calls(side):
            rows = []
            for line in side.splitlines():
                if not line.strip():
                    continue
                found = re.fullmatch(r"\s*([A-Za-z_][A-Za-z0-9_]*)\(.*\)\s*", line)
                if not found or found.group(1) not in exports:
                    raise ValueError(UNION_REFUSAL + ": audit registration conflict is not additive")
                rows.append(line)
            return rows

        lines = calls(match.group(1))
        for line in calls(match.group(2)):
            if line not in lines:
                lines.append(line)
        return "\n".join(lines) + ("\n" if lines else "")

    result = _HUNK.sub(call_union, merged)
    if re.search(r"^(?:<<<<<<<|=======|>>>>>>>)", result, re.M):
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not additive")
    missing = [export for export in exports if f"{export}(" not in result]
    if missing:
        raise ValueError(UNION_REFUSAL + ": missing sibling call " + ", ".join(missing))
    return result


def _resolve_quoted_list(working, pattern, names, quote):
    match = pattern.search(working)
    if not match:
        raise ValueError(UNION_REFUSAL + ": missing sibling name list")
    if not names:
        raise ValueError(UNION_REFUSAL + ": sibling name list is empty")
    hunks = list(_HUNK.finditer(working))
    if not hunks or any(
        hunk.start() < match.start(1) or hunk.end() > match.end(1) for hunk in hunks
    ):
        raise ValueError(UNION_REFUSAL + ": sibling registration conflict is not additive")
    indent = "    "
    for line in match.group(1).splitlines():
        quoted = re.match(r"""^(\s*)(['"])""", line)
        if quoted:
            indent = quoted.group(1)
            break
    close = ""
    trailing = re.search(r"\n([ \t]*)$", match.group(1))
    if trailing:
        close = trailing.group(1)
    lead = "\n" if match.group(1).startswith("\n") else ""
    rendered = lead + "\n".join(f"{indent}{quote}{name}{quote}," for name in names) + "\n" + close
    return working[:match.start(1)] + rendered + working[match.end(1):]


def _resolve_registration(root, name):
    from manifest_union import _stage_texts, union_strings
    base_text, ours_text, theirs_text = _stage_texts(root, name)
    working = repository_docs.local(root, name).read_text()
    if name.endswith("launch-ui-regression-audit.py"):
        return _resolve_audit_python(working, _union_triples(base_text, ours_text, theirs_text))
    pattern = _PY_LIST if name.endswith("test_launch_ui_regression_audit.py") else _TS_LIST
    ours_names = _quoted_names(ours_text, pattern)
    names = union_strings(
        _quoted_names(base_text, pattern),
        ours_names,
        _quoted_names(theirs_text, pattern),
    )
    quote = re.search(r"""(['"])[^'"]+\1""", pattern.search(ours_text).group(1)).group(1)
    return _resolve_quoted_list(working, pattern, names, quote)


