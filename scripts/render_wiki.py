#!/usr/bin/env python3
"""Render reviewed public docs into the flat GitHub Wiki page namespace."""
import argparse
import os
import posixpath
import re
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

# The repository being published (a fork publishes its own links).
SLUG = os.environ.get("GITHUB_REPOSITORY") or "jirbis/mac-intel-local-ai"
REPO = f"https://github.com/{SLUG}"
BLOB = REPO + "/blob/main/"
RAW = f"https://raw.githubusercontent.com/{SLUG}/main/"
PAGES = {
    "docs/wiki/Home.md": "Home",
    "docs/wiki/Getting-Started.md": "Getting-Started",
    "docs/wiki/Hex-Integration.md": "Hex-Integration",
    "docs/wiki/Troubleshooting.md": "Troubleshooting",
    "docs/backends.md": "Backends",
    "docs/benchmarks.md": "Benchmarks",
    "docs/compatibility.md": "Compatibility",
}
LINK = re.compile(r"(!?\[[^\]\n]+\]\()([^\s()]+)(\))")
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")


def rewrite_target(target, source, root, image=False):
    parsed = urlsplit(target)
    if target.startswith(BLOB):
        candidate = unquote(parsed.path.split("/blob/main/", 1)[1])
    elif parsed.scheme or parsed.netloc or target.startswith("#"):
        return target
    else:
        candidate = posixpath.normpath(
            posixpath.join(posixpath.dirname(source), unquote(parsed.path))
        )
    if candidate == ".." or candidate.startswith("../") or candidate.startswith("/"):
        raise ValueError(f"{source}: link outside repository: {target}")
    suffix = ("?" + parsed.query if parsed.query else "") + (
        "#" + parsed.fragment if parsed.fragment else ""
    )
    if not image:
        for path in (candidate, candidate + ".md"):
            if path in PAGES:
                return PAGES[path] + suffix
    if not (root / candidate).is_file() and not (root / candidate).is_dir():
        raise ValueError(f"{source}: unresolved local link: {target}")
    return (RAW if image else BLOB) + quote(candidate, safe="/") + suffix


def render_page(text, source, root):
    rendered = []
    fence = None
    for line in text.splitlines(keepends=True):
        match = FENCE.match(line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not line[match.end():].strip():
                fence = None
            rendered.append(line)
        elif fence:
            rendered.append(line)
        else:
            rendered.append(LINK.sub(
                lambda m: m[1] + rewrite_target(m[2], source, root, m[1].startswith("!")) + m[3],
                line
            ))
    return ("<!-- Managed by docs-to-wiki; edit the source via pull request. -->\n"
            f"> Maintained in [the source repository]({BLOB}{source}). "
            "Changes here may be overwritten by documentation sync.\n\n"
            + "".join(rendered).rstrip() + "\n")


def render(root, output):
    actual = {p.relative_to(root).as_posix() for p in (root / "docs").rglob("*.md")}
    expected = set(PAGES)
    if actual != expected:
        raise ValueError(f"Update the public page map: missing={sorted(expected-actual)}, "
                         f"unmapped={sorted(actual-expected)}")
    if len(set(PAGES.values())) != len(PAGES):
        raise ValueError("Wiki page name collision")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Use an empty output directory")
    pages = {}
    for source, page in PAGES.items():
        path = root / source
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Invalid source: {source}")
        pages[page + ".md"] = render_page(path.read_text(encoding="utf-8"), source, root)
    output.mkdir(parents=True, exist_ok=True)
    for name, content in pages.items():
        (output / name).write_text(content, encoding="utf-8")
    print("Rendered:", ", ".join(sorted(pages)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    render(args.root, args.output)
