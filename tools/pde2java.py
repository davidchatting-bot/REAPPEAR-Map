#!/usr/bin/env python3
"""Combine a Processing sketch's .pde tabs into a single compilable Java file.

Stands in for the Processing IDE's preprocessor, which the Pi doesn't have (and
whose parser predates syntax this sketch uses, e.g. try-with-resources). The
sketch is already written as plain Java, so only the mechanical parts are
needed: nest every tab in one PApplet subclass, hoist imports, add `public` to
methods, move size() into settings(), and append a main().

usage: pde2java.py <sketch_dir> <output.java> [--class NAME]
"""
import argparse
import re
import sys
from pathlib import Path

CORE_IMPORTS = [
    "processing.core.*",
    "processing.data.*",
    "processing.event.*",
    "processing.opengl.*",
]
DEFAULT_IMPORTS = [
    "java.util.HashMap",
    "java.util.ArrayList",
    "java.io.File",
    "java.io.BufferedReader",
    "java.io.InputStreamReader",
    "java.io.PrintWriter",
    "java.io.InputStream",
    "java.io.OutputStream",
    "java.io.IOException",
]

IMPORT_RE = re.compile(r"^[ \t]*import[ \t]+([\w.]+(?:\.\*)?)[ \t]*;[ \t]*\r?$", re.M)
ACCESS = {"public", "private", "protected"}
NOT_A_METHOD_START = {"if", "for", "while", "switch", "catch", "try", "else", "do",
                      "synchronized", "return", "new", "throw"}


def extract_imports(text):
    imports = [m.group(1) for m in IMPORT_RE.finditer(text)]
    # Blank the lines rather than deleting them so line numbers still match the .pde.
    return imports, IMPORT_RE.sub("", text)


def blank_noncode(text):
    """Return text with comments and string/char literals replaced by spaces
    (newlines kept), so brace and signature analysis can't be fooled by them."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "//":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif two == "/*":
            while i < n and text[i:i + 2] != "*/":
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            for j in (i, i + 1):
                if j < n:
                    out[j] = " "
            i += 2
        elif c in "\"'":
            quote = c
            out[i] = " "
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    out[i] = " "
                    i += 1
                if i < n and text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
            i += 1
        else:
            i += 1
    return "".join(out)


FLOAT_LITERAL_RE = re.compile(r"(?<![\w.])(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?(?![\w.])")
PARSE_CAST_RE = re.compile(r"\b(int|float|boolean|byte|char)(\s*)\(")


def processing_syntax(text):
    """Processing's two literal-level conveniences: a decimal literal with no
    suffix is a float (0.5 -> 0.5f), and int()/float()/... are function-style
    casts (float(x) -> PApplet.parseFloat(x))."""
    code = blank_noncode(text)
    edits = []  # (position, length replaced, replacement)
    for m in FLOAT_LITERAL_RE.finditer(code):
        edits.append((m.end(), 0, "f"))
    for m in PARSE_CAST_RE.finditer(code):
        name = m.group(1)
        edits.append((m.start(), len(name), "PApplet.parse" + name.capitalize()))
    for pos, length, repl in sorted(edits, reverse=True):
        text = text[:pos] + repl + text[pos + length:]
    return text


def add_public(text, class_names):
    """Insert `public` before member-level method declarations lacking an
    access modifier. Member level = directly inside the tab (depth 0) or
    directly inside a class body. Constructors are left alone, as Processing does."""
    code = blank_noncode(text)
    inserts = []
    stack = []  # 'class' | 'other'
    stmt_start = None
    for i, c in enumerate(code):
        if c.isspace():
            continue
        if stmt_start is None:
            stmt_start = i
        if c == ";" or c == "}":
            if c == "}" and stack:
                stack.pop()
            stmt_start = None
        elif c == "{":
            member_level = not stack or stack[-1] == "class"
            stmt = code[stmt_start:i]
            kind = "other"
            if re.search(r"\bclass\b", stmt) and member_level:
                kind = "class"
            elif member_level and "=" not in stmt:
                words = re.findall(r"[\w.<>\[\]?,]+", stmt.split("(")[0])
                is_signature = re.search(r"\)\s*(throws\s+[\w.,\s]+)?\s*$", stmt)
                head = words[0] if words else ""
                ctor = len(words) == 1 and words[0] in class_names
                if (is_signature and head not in NOT_A_METHOD_START and not ctor
                        and not (ACCESS & set(words))):
                    inserts.append(stmt_start)
            stack.append(kind)
            stmt_start = None
    for pos in sorted(inserts, reverse=True):
        text = text[:pos] + "public " + text[pos:]
    return text


def hoist_size(text):
    """Move the size()/fullScreen() call out of setup() into settings()."""
    setup = re.search(r"\bvoid\s+setup\s*\(\s*\)\s*\{", text)
    if not setup:
        return text, None
    call = re.compile(r"^[ \t]*((?:size|fullScreen)\s*\([^;]*\)\s*;)[ \t]*\r?$", re.M)
    m = call.search(text, setup.end())
    if not m:
        return text, None
    return text[:m.start()] + text[m.end():], m.group(1)


def combine(sketch_dir, class_name):
    sketch_dir = Path(sketch_dir)
    main = sketch_dir / f"{class_name}.pde"
    if not main.exists():
        sys.exit(f"main tab not found: {main}")
    tabs = [main] + sorted(p for p in sketch_dir.glob("*.pde") if p != main)

    imports, bodies = [], []
    for tab in tabs:
        found, body = extract_imports(tab.read_text(encoding="utf-8"))
        for imp in found:
            if imp not in imports:
                imports.append(imp)
        bodies.append(body)
    body = "\n".join(bodies)

    class_names = {class_name} | set(re.findall(r"^\s*class\s+(\w+)", body, re.M))
    body, size_call = hoist_size(body)
    body = processing_syntax(body)
    body = add_public(body, class_names)

    lines = [f"import {i};" for i in CORE_IMPORTS] + [""]
    lines += [f"import {i};" for i in imports] + [""]
    lines += [f"import {i};" for i in DEFAULT_IMPORTS if i not in imports] + [""]
    lines.append(f"public class {class_name} extends PApplet {{")
    lines.append("")
    lines.append(body.rstrip("\n"))
    if size_call:
        lines.append(f"  public void settings() {{  {size_call} }}")
    lines += [
        "  static public void main(String[] passedArgs) {",
        '    String[] appletArgs = new String[] { "--present", "--window-color=#666666", '
        f'"--hide-stop", "{class_name}" }};',
        "    if (passedArgs != null) {",
        "      PApplet.main(concat(appletArgs, passedArgs));",
        "    } else {",
        "      PApplet.main(appletArgs);",
        "    }",
        "  }",
        "}",
        "",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sketch_dir")
    ap.add_argument("output")
    ap.add_argument("--class", dest="class_name", default="TheMap")
    args = ap.parse_args()
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(combine(args.sketch_dir, args.class_name), encoding="utf-8")
