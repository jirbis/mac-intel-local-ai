import tempfile
import unittest
from pathlib import Path

from render_wiki import PAGES, render, render_page


class WikiRenderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for source in PAGES:
            path = self.root / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# Test\n", encoding="utf-8")
        (self.root / "example.py").write_text("print(1)\n", encoding="utf-8")

    def test_all_pages_and_deterministic_output(self):
        a, b = self.root / "a", self.root / "b"
        render(self.root, a)
        render(self.root, b)
        self.assertEqual({p.name for p in a.iterdir()}, {v + ".md" for v in PAGES.values()})
        self.assertEqual({p.name: p.read_bytes() for p in a.iterdir()},
                         {p.name: p.read_bytes() for p in b.iterdir()})

    def test_links_and_fences(self):
        source = "docs/wiki/Home.md"
        text = ("[Getting started](Getting-Started) [Backend](../backends.md#setup)\n"
                "[Benchmark](https://github.com/jirbis/mac-intel-local-ai/blob/main/docs/benchmarks.md)\n"
                "[Code](../../example.py) [External](https://example.com)\n"
                "```md\n[x](nonexistent.md)\n```\n")
        result = render_page(text, source, self.root)
        self.assertIn("[Getting started](Getting-Started)", result)
        self.assertIn("[Backend](Backends#setup)", result)
        self.assertIn("[Benchmark](Benchmarks)", result)
        self.assertIn("[Code](https://github.com/jirbis/mac-intel-local-ai/blob/main/example.py)", result)
        self.assertIn("[External](https://example.com)", result)
        self.assertIn("[x](nonexistent.md)", result)

    def test_unmapped_file_fails_closed(self):
        (self.root / "docs/private-notes.md").write_text("not approved", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "unmapped"):
            render(self.root, self.root / "out")
        self.assertFalse((self.root / "out").exists())

    def test_invalid_link_fails(self):
        with self.assertRaisesRegex(ValueError, "unresolved"):
            render_page("[missing](missing.md)", "docs/wiki/Home.md", self.root)


if __name__ == "__main__":
    unittest.main()
