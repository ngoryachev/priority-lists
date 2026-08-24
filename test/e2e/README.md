# End-to-end smoke test

Drives the deployed web app in a real browser and checks the tree flows that
widget tests cannot reach: routing between levels, persistence across a reload,
and what the server actually stored.

It caught the bug widget tests missed — a pushed route is built outside the
provider scope created after sign-in, which left every level below the top
blank in release builds.

## Running

```bash
npm install playwright          # browsers come from the system Chrome channel
node test/e2e/tree_flow.js      # exits non-zero if any check fails
```

Targets `http://65.21.0.66:8000/` as the user in `lib.js`. The run creates and
then deletes its own subtree; it leaves nothing behind on success.

## Driving Flutter web

The app renders to canvas, so there is no DOM to query until the accessibility
tree is switched on — `enableSemantics()` clicks the hidden
`flt-semantics-placeholder` that Flutter publishes for screen readers. After
that:

* a card is one `flt-semantics` node labelled `"<priority>\n[<count>]\n<title>\n<chips>"`;
* a tooltip becomes the node's **text**, not an `aria-label`;
* text fields only sync while focused, so type with the keyboard after a click
  rather than `fill()`;
* plain `Text` widgets — the empty-state line, an `AlertDialog` body — are not
  published at all, so assert those against the server or a screenshot.
