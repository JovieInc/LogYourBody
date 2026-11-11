"""Prepare dependency release notes for review without changing a remote PR."""
import html
import re


def dependency_pr_body(text):
    def code_span(match):
        original = match[1]
        content = html.unescape(original)
        if "<" in original or any(char in content for char in "`\r\n"):
            raise ValueError("dependency PR body requires plain, single-line HTML code spans")
        # Markdown strips one surrounding space when both ends contain spaces.
        if content.startswith(" ") and content.endswith(" ") and content.strip():
            content = " " + content + " "
        return "`" + content + "`"

    # Preserve existing Markdown code exactly, matching the pinned mention guard.
    parts = re.split(r"(```[\s\S]*?```|`[^`\n]*`)", text)
    for index in range(0, len(parts), 2):
        parts[index] = re.sub(r"<code>(.*?)</code>", code_span, parts[index], flags=re.S | re.I)
        if re.search(r"</?code\b", parts[index], re.I):
            raise ValueError("dependency PR body contains an unsupported HTML code span")
    return "".join(parts)
