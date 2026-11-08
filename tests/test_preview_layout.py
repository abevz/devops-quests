"""The native disclosure keeps launch essentials available before expansion."""
from html.parser import HTMLParser
from pathlib import Path


class PreviewLayout(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.stack = []
        self.nodes = {}
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.nodes[attrs["id"]] = (tag, attrs, tuple(self.stack))
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}:
            self.stack.append(attrs.get("id", tag))

    def handle_endtag(self, tag):
        if self.stack:
            self.stack.pop()


def test_preview_disclosure_keeps_launch_essentials_outside():
    root = Path(__file__).resolve().parents[1]
    layout = PreviewLayout((root / "web/index.html").read_text())
    tag, attrs, _ = layout.nodes["preview-resources"]
    assert tag == "details"
    assert "open" not in attrs
    for name in ("preview-mode-control", "preview-play-mode", "preview-time", "preview-sandbox", "preview-availability", "preview-run"):
        assert "preview-resources" not in layout.nodes[name][2]
        assert "preview" in layout.nodes[name][2]
    for name in ("preview-dependencies", "preview-facts", "preview-score", "preview-best"):
        assert "preview-resources" in layout.nodes[name][2]
