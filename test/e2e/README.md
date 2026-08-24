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
node test/e2e/tree_flow.js      # desktop viewport, mouse input
node test/e2e/mobile_flow.js    # Pixel 7 viewport, real touch events
```

Both exit non-zero if any check fails, target `http://65.21.0.66:8000/`, and
sign up their throwaway account on first run. Each creates and then deletes its
own subtree, leaving nothing behind on success. Screenshots land in the system
temp dir.

`mobile_flow.js` additionally checks that nothing overflows horizontally at
depth, in portrait or landscape, and that every breadcrumb clears a 44px tap
target. The dense card and app-bar controls (the 1..4 rows at 32px, the card
action icons at 40px) predate the tree, so they are reported rather than
asserted.

## On a real Android device

`integration_test/tree_flow_test.dart` runs the same flow natively — Supabase
client, real gestures, no browser:

```bash
flutter test integration_test/tree_flow_test.dart \
  --dart-define-from-file=.env.json -d <device-or-emulator>
```

Two gotchas that cost real debugging time there: a bare `Text` does not hit
test, so tap the enclosing `InkWell` (tapping a card's title silently misses),
and tapping a `SegmentedButton` segment through its label dismisses the dialog
instead of selecting.

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
