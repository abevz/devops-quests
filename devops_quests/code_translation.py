"""Compare guide code while allowing translation of explanatory text only.

This is a lexical contract, not a code formatter or an execution validator.
Unknown fence languages and command output remain byte-for-byte snapshots.
"""

import re

import yaml

LANGUAGES = {
    "hcl",
    "terraform",
    "bash",
    "sh",
    "yaml",
    "yml",
    "go",
    "python",
    "py",
    "json",
    "mermaid",
    "filetree",
}
DESCRIPTIONS = {"description", "error_message"}
CALLS = {
    "print",
    "Printf",
    "Println",
    "Errorf",
    "ValueError",
    "RuntimeError",
    "Exception",
}
PROTECTED = re.compile(
    r"\$(?:[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[?@*#$!_-])|"
    r"%(?:\([^)]+\))?[-+ #0-9.*\[\]$hljztL]*[a-zA-Z%]|\\.|"
    r"</?[A-Za-z][^<>]*>|&&|\|\||[;&<>|]|"
    r"https?://[^\s\"']+|(?<![\w>])(?:~|\.{1,2})?/[^\s\"',;<>]+|"
    r"\b[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+\b|`[^`]+`|[0-9]+"
)
# Existing Latin fragments in a Russian explanation can be commands, flags or
# identifiers. Preserve them generically rather than guessing command names.
LATIN_FRAGMENT = re.compile(
    r"[-+./]*[A-Za-z_][A-Za-z_0-9./:=+@~-]*"
    r"(?:[ \t]+[-+./]*[A-Za-z_][A-Za-z_0-9./:=+@~-]*)*"
)


def fenced_blocks(text):
    result, block, marker = [], [], None
    for line in text.splitlines():
        match = re.match(r"^\s*(?:>\s*)*(`{3,}|~{3,})", line)
        if marker is None and match:
            marker = match[1][0]
            block = [line]
        elif marker is not None:
            block.append(line)
            if match and match[1][0] == marker:
                result.append("\n".join(block))
                marker = None
    if marker is not None:
        raise ValueError("Unclosed fenced code block")
    return result


def protected(text):
    result, i = [], 0
    while i < len(text):
        # Interpolations contain operational expressions, including nested
        # substitutions. Keep the complete balanced expression verbatim.
        prefix = next(
            (p for p in ("$${", "${", "$(", "%{", "{") if text.startswith(p, i)), None
        )
        if prefix:
            start = i
            stack = [")" if prefix.endswith("(") else "}"]
            i += len(prefix)
            quote = None
            while i < len(text) and stack:
                c = text[i]
                if c == "\\":
                    i += 2
                    continue
                if quote:
                    if c == quote:
                        quote = None
                elif c in "\"'`":
                    quote = c
                elif c in "({[":
                    stack.append({"(": ")", "{": "}", "[": "]"}[c])
                elif c == stack[-1]:
                    stack.pop()
                i += 1
            if stack:
                raise ValueError("Unclosed explanatory-text interpolation")
            result.append(text[start:i])
            continue
        match = PROTECTED.match(text, i)
        if match:
            result.append(match[0])
            i = match.end()
        else:
            i += 1
    return tuple(result)


def code_tokens(language, code, explanations=None):
    """Keep token order/count, delimiters, whitespace and operational literals."""
    if language not in LANGUAGES:
        return (("exact", code),)
    result, significant, line, calls = [], [], [], []
    literals = structured_literals(language, code)
    sequence = language == "mermaid" and code.lstrip().startswith("sequenceDiagram")
    i = 0

    def add(kind, raw, value=None):
        result.append((kind, raw if value is None else value))
        if kind in {"human", "comment"} and explanations is not None:
            explanations.append(raw)
        if kind not in {"space", "comment"}:
            significant.append(raw)
            line.append(raw)

    def human():
        if len(significant) >= 2:
            key, separator = significant[-2:]
            key = key.strip("\"'")
            if (
                language in {"hcl", "terraform"}
                and separator == "="
                and key in DESCRIPTIONS
            ):
                return True
        if language in {"bash", "sh"}:
            remaining = code[i:].split("\n", 1)[0]
            # Redirected/piped data is configuration, not a console message.
            data_output = re.search(r"\||>(?!&[12](?:\s|$))", remaining)
            if not line or data_output:
                return False
            return line[0] == "echo" or (line[0] == "printf" and len(line) == 1)
        if language == "mermaid":
            if sequence and line:
                if line[0] in {"participant", "actor"} and line[-1] == "as":
                    return True
                if line[-1] == ":" and any("-" in token for token in line):
                    return True
            return bool(significant and significant[-1] in {"[", "(", "{", "|"})
        if language in {"python", "py", "go"} and calls and calls[-1] in CALLS:
            # Only a direct first message/format literal is explanatory.
            # Subsequent printf data, print kwargs and nested containers are
            # operational values, including **{"sep": " "} in Python.
            if significant[-1] == "(":
                return True
            return (
                language in {"python", "py"}
                and significant[-1].lower() in {"f", "r", "fr", "rf", "u"}
                and len(significant) > 1
                and significant[-2] == "("
            )
        return False

    while i < len(code):
        start = i
        c = code[i]
        if c.isspace():
            while i < len(code) and code[i].isspace():
                i += 1
            raw = code[start:i]
            add("space", raw)
            if "\n" in raw:
                line.clear()
            continue
        if i in literals:
            end, style = literals[i]
            raw = code[i:end]
            add("human", raw, (style, protected(raw)))
            i = end
            continue
        hash_comment = (
            c == "#"
            and language
            in {
                "hcl",
                "terraform",
                "bash",
                "sh",
                "yaml",
                "yml",
                "python",
                "py",
                "filetree",
            }
            and (
                language in {"hcl", "terraform", "python", "py"}
                or i == 0
                or code[i - 1].isspace()
            )
        )
        slash_comment = language in {"hcl", "terraform", "go"} and code[i : i + 2] in {
            "//",
            "/*",
        }
        if hash_comment or slash_comment:
            prefix = "#" if hash_comment else code[i : i + 2]
            if prefix == "/*":
                end = code.find("*/", i + 2)
                if end < 0:
                    raise ValueError("Unclosed block comment")
                i = end + 2
            else:
                end = code.find("\n", i)
                i = len(code) if end < 0 else end
            raw = code[start:i]
            add("comment", raw, (prefix, protected(raw)))
            continue
        if sequence and human() and c not in "\"'":
            end = code.find("\n", i)
            end = len(code) if end < 0 else end
            raw = code[i:end]
            add("human", raw, ("display", protected(raw)))
            i = end
            continue
        quotes = ("'", '"') + (("`",) if language == "go" else ())
        if c in quotes:
            quote = (
                c * 3
                if language in {"python", "py"} and code[i : i + 3] == c * 3
                else c
            )
            i += len(quote)
            while i < len(code):
                if code.startswith(quote, i):
                    # YAML escapes single quotes by doubling them.
                    if (
                        language in {"yaml", "yml"}
                        and quote == "'"
                        and code[i : i + 2] == "''"
                    ):
                        i += 2
                        continue
                    i += len(quote)
                    break
                if code[i] == "\\" and quote not in {"'", "`"}:
                    i += 2
                else:
                    i += 1
            else:
                raise ValueError("Unclosed string literal")
            raw = code[start:i]
            allowed = human()
            add(
                "human" if allowed else "string",
                raw,
                (quote, protected(raw)) if allowed else None,
            )
            continue
        word = re.match(r"[\w-]+", code[i:])
        if word:
            raw = word[0]
            i += len(raw)
            add("word", raw)
            continue
        if c == "(":
            calls.append(significant[-1] if significant else "")
        elif c == ")" and calls:
            calls.pop()
        add("symbol", c)
        i += 1
        if c in ";|":
            line.clear()
    return tuple(result)


def structured_literals(language, code):
    """Locate descriptive YAML/JSON values; data payloads remain operational."""
    if language not in {"yaml", "yml", "json"}:
        return {}
    try:
        if any(
            isinstance(token, (yaml.tokens.AnchorToken, yaml.tokens.AliasToken))
            for token in yaml.scan(code)
        ):
            return {}
        documents = list(yaml.compose_all(code))
    except yaml.YAMLError:
        # Partial examples still support comment translation, never blind masking.
        return {}
    spans = {}

    def visit(node, path=()):
        if isinstance(node, yaml.MappingNode):
            for key, value in node.value:
                if isinstance(key, yaml.ScalarNode):
                    visit(value, (*path, key.value))
        elif isinstance(node, yaml.SequenceNode):
            for item in node.value:
                visit(item, path)
        elif isinstance(node, yaml.ScalarNode) and node.tag.endswith(":str") and path:
            if any(
                key in {"data", "stringData", "binaryData", "default"}
                for key in path[:-1]
            ):
                return
            field = path[-1]
            message = (
                field == "msg"
                and language != "json"
                and (
                    len(path) == 1
                    or any(
                        key
                        in {
                            "debug",
                            "ansible.builtin.debug",
                            "fail",
                            "ansible.builtin.fail",
                            "assert",
                            "ansible.builtin.assert",
                        }
                        for key in path[:-1]
                    )
                )
            )
            if field in DESCRIPTIONS or message:
                spans[node.start_mark.index] = (
                    node.end_mark.index,
                    node.style or "plain",
                )

    for document in documents:
        if document is not None:
            visit(document)
    return spans


def same_code(original, translated):
    left, right = fenced_blocks(original), fenced_blocks(translated)
    if len(left) != len(right):
        return False
    for source, target in zip(left, right, strict=True):
        a, b = source.splitlines(), target.splitlines()
        if a[0] != b[0] or a[-1] != b[-1]:
            return False
        match = re.match(r"^\s*(?:>\s*)*(?:`{3,}|~{3,})(\S*)", a[0])
        language = match[1]
        # A callout's quote markers belong to Markdown, not to the code.
        # Compare wrappers separately so removing them cannot hide edits.
        depth = re.match(r"^[ \t]*(?:>[ \t]*)*", a[0])[0].count(">")
        wrappers_a, body_a = quoted_body(a[1:-1], depth)
        wrappers_b, body_b = quoted_body(b[1:-1], depth)
        if wrappers_a != wrappers_b:
            return False
        if language == "text" and file_layout(body_a):
            if not file_layout(body_b):
                return False
            language = "filetree"
        original_text, translated_text = [], []
        if code_tokens(language, body_a, original_text) != code_tokens(
            language, body_b, translated_text
        ):
            return False
        if len(original_text) != len(translated_text):
            return False
        for before, after in zip(original_text, translated_text, strict=True):
            # Diagram labels are display text, not executable messages. Their
            # actor/graph identifiers remain separate, exact lexical tokens.
            if language != "mermaid" and not preserves_fragments(before, after):
                return False
    return True


def quoted_body(lines, depth):
    """Remove only the enclosing blockquote depth; keep code indentation."""
    wrappers, body = [], []
    prefix = re.compile(r"(?:[ \t]*> ?){" + str(depth) + r"}")
    for line in lines:
        match = prefix.match(line) if depth else None
        wrapper = match[0] if match else ""
        wrappers.append(wrapper)
        body.append(line[len(wrapper) :])
    return wrappers, "\n".join(body)


def preserves_fragments(original, translated):
    """Retain existing technical text even when it is not marked as inline code.

    A Latin phrase already present in the source is not Russian prose needing
    translation. Require it verbatim and in order. This intentionally fails
    closed on ambiguous mixed prose, without a command-name allowlist.
    """
    cursor = 0
    for match in LATIN_FRAGMENT.finditer(original):
        fragment = match[0]
        found = re.search(
            r"(?<![\w./:=+@~-])" + re.escape(fragment) + r"(?![\w./:=+@~-])",
            translated[cursor:],
        )
        if found is None:
            return False
        cursor += found.end()
    return True


def file_layout(body):
    """Recognize annotated path-only layouts, never console transcripts."""
    paths, annotated = [], False
    for line in body.splitlines():
        line = re.sub(r"^[\s│├└─]+", "", line)
        if not line:
            continue
        split = re.split(r"\s+#", line, maxsplit=1)
        annotated |= len(split) == 2
        path = split[0].strip()
        if not re.fullmatch(r"[\w./-]+", path):
            return False
        paths.append(path)
    return annotated and len(paths) >= 2 and any("/" in path for path in paths)
