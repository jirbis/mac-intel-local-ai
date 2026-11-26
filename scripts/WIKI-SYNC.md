# Publishing documentation to GitHub Wiki

The Markdown pages under docs/ are the source of truth. The [Wiki](https://github.com/jirbis/mac-intel-local-ai/wiki) is a generated publication of the reviewed main branch.

- Edit documentation through pull requests. The existing source-page navigation is unchanged; the renderer adapts links for Wiki.
- All seven current Markdown pages under docs/ are included. The explicit public-page map in scripts/render_wiki.py must be updated in the same PR when documentation is added, renamed or removed. This prevents accidentally publishing internal notes. README and BACKLOG stay in the source repository.
- The workflow renders pages, tests link conversion and validates the page map. It updates only those seven page names, preserves other Wiki pages/assets/sidebar and never force-pushes or deletes pages. Remove obsolete Wiki pages explicitly after review. Direct edits to mapped Wiki pages may be overwritten.
- The workflow runs on merged PRs to main (not unmerged feature commits), using the current trusted main branch and a serialized publication job. The existing Intel build/release workflow is unchanged. The Wiki uses GitHub's built-in token with contents:write; no long-lived PAT is configured.

## First publication

1. Merge documentation PR #3 before the Wiki sync PR (if #3 is squash-merged, review/retarget the stacked PR to main before merge).
2. If the Wiki is empty, create its first Home page in the GitHub Wiki UI. Ensure Wiki editing is restricted to collaborators in repository settings.
3. After the sync workflow is on main, open Actions → Sync documentation to Wiki → Run workflow → main → check. This validates without writing Wiki content.
4. Choose publish to perform the initial sync. Inspect the seven Wiki pages and their links, then run publish again; the second run should report Wiki is already up to date if nothing changed.
5. Subsequent merged documentation PRs are published automatically. A clone/push failure is visible in Actions; no force push or token escalation is attempted.

## Local validation

From repository root, run `python3 -m unittest discover -s scripts -p 'test_render_wiki.py'` and `python3 scripts/render_wiki.py --output /tmp/mac-intel-wiki-preview` (use a new or empty output directory). No Wiki credentials are required for local rendering.

If a future doc needs Markdown link syntax not supported by the current renderer (e.g. complex destinations or reference-style links), extend tests and conversion in its PR. Screenshots remain subject to review and redaction before public publication.
