"""The briefing keeps launch essentials and personal best visible in its aside."""
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


def test_preview_aside_keeps_launch_essentials_and_best_without_disclosure():
    root = Path(__file__).resolve().parents[1]
    layout = PreviewLayout((root / "web/index.html").read_text())
    for name in ("preview-resources", "preview-dependencies", "preview-facts", "preview-score"):
        assert name not in layout.nodes
    for name in ("preview-mode-control", "preview-play-mode", "preview-time", "preview-sandbox", "preview-best", "preview-availability", "preview-run"):
        ancestors = layout.nodes[name][2]
        assert "preview" in ancestors
        assert "aside" in ancestors
        assert "details" not in ancestors
    tag, attrs, _ = layout.nodes["preview-best"]
    assert tag == "p"
    assert "hidden" in attrs
    ids = list(layout.nodes)
    assert ids.index("preview-best") + 1 == ids.index("preview-availability")
