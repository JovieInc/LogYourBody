"""Propose conservative Python function merges without writing files."""
import ast
import re
import subprocess
import tempfile
import textwrap
from pathlib import Path

from json_union import _unmerged_texts


def union_python(root, name):
    """Propose a reviewed union of independently inserted Python functions."""
    if not name.endswith(".py"):
        raise ValueError("Python union requires a .py path")
    base, ours, theirs = _unmerged_texts(root, name, "Python union")
    with tempfile.TemporaryDirectory() as directory:
        files = []
        for index, source in enumerate((ours, base, theirs)):
            path = Path(directory) / str(index)
            path.write_text(source)
            files.append(str(path))
        merged = subprocess.run(["git", "merge-file", "-p", "--diff3", *files], capture_output=True, text=True)
    if not 1 <= merged.returncode <= 127:
        raise ValueError("Python union requires a merge with one or more conflicts")
    pattern = re.compile(r"(?ms)^<<<<<<< [^\n]*\n(.*?)^\|\|\|\|\|\|\| [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n")
    def combine(match):
        left, ancestor, right = match.groups()
        if ancestor.strip():
            raise ValueError("Python union refuses changes to existing code")
        names = []
        for block in (left, right):
            try:
                nodes = ast.parse(textwrap.dedent(block)).body
            except SyntaxError as exc:
                raise ValueError("Python union requires complete functions") from exc
            if not nodes or any(not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) for node in nodes):
                raise ValueError("Python union requires complete functions")
            names.extend(node.name for node in nodes)
        if len(names) != len(set(names)):
            raise ValueError("Python union refuses duplicate function names")
        return left + right
    result, count = pattern.subn(combine, merged.stdout)
    if not count or re.search(r"(?m)^(?:<{7}|\|{7}|={7}|>{7})", result):
        raise ValueError("Python union refuses unresolved conflict markers")
    try:
        ast.parse(result)
    except SyntaxError as exc:
        raise ValueError("Python union produced invalid Python") from exc
    return result
