# The verification loop

How a change gets proven in this repository, for any agent and any tool. Three
layers, in order of cost. A change is not done because the first one passed.

1. **Static and unit** (`bin/check`): seconds. Never skipped.
2. **Visual** (preview catalog + screenshots): for a component or a screen.
3. **End to end** (dusk driving a real Chrome): for anything a person clicks, at
   desktop and at mobile width both.

## 1. The static gate

```sh
bin/check              # everything, in parallel
bin/check --fast       # analyze + pint only
bin/check flutter      # one half; also backend
```

## 2. The visual loop, for components and screens

```
CREATE -> SCREENSHOT -> ANALYZE -> FIX -> VERIFY
```

Three rounds maximum. Stop and surface the problem if a full round produces no
improvement, rather than looping on the same finding.

- **CREATE** using semantic tokens and existing components. Check
  `docs/component-registry.md` before building a new widget.
- **SCREENSHOT** light and dark, from the preview catalog:

  ```sh
  ./bin/fsa dusk:navigate --route=/preview
  ./bin/fsa dusk:screenshot -o .ac/evidence/<name>-light.png
  # switch the catalog to dark, then:
  ./bin/fsa dusk:screenshot -o .ac/evidence/<name>-dark.png
  ```

- **ANALYZE** with the `component-visual-reviewer` reviewer
  (`.claude/agents/component-visual-reviewer.md` for Claude Code; other tools can
  read that file as the scoring rubric). It scores token compliance, dark/light
  parity, spacing, typography, and radii, and returns BLOCKING and ADVISORY items.
- **FIX** every BLOCKING item. ADVISORY items only when they need no scope creep.
- **VERIFY** by re-screenshotting and re-scoring.

## 3. The end-to-end walk with dusk

`fluttersdk_dusk` drives a running Flutter app over VM Service extensions: it
reads the Semantics tree as a YAML snapshot with stable `[ref=eN]` handles and
dispatches real gestures through a six-check actionability gate.

Boot the backend, then the app:

```sh
cd backend && php artisan serve --port=8000
./bin/fsa start --device=chrome --cdp-port=9223
```

Three boot failures read as "the app is broken" rather than as a missing service:

- **PostgreSQL**, which the backend now requires for dev AND tests (D72). A stopped server fails
  every request and the whole backend suite with `Connection refused`, which reads like a broken
  build. `brew services start postgresql@17`. The databases are `depools` and `depools_testing`, and
  the instance needs `vector`, `pg_trgm` and `unaccent` available (`brew install pgvector` covers the
  first).

- **Redis**, when the backend's cache or rate limiter is configured for it. Every
  API call 500s on `Connection refused`, login included. `redis-server --port 6379`
  is enough.
- **Reverb**, when `.env` sets `BROADCAST_CONNECTION=reverb`. The boot-time Echo
  connect throws an uncaught exception if the socket refuses, and that kills the
  whole Flutter boot: nothing renders, the snapshot is empty, and there is no error
  on screen. The tell is a console showing Env / Cache / Database / Locale ready
  and then a WebSocket error. `php artisan reverb:start --port=8080`.

If `fsa start` times out on a cold web build, run `flutter run -d chrome` yourself
and write `~/.artisan/state.json` with the `pid`, `vmServiceUri`, `webPort`,
`vmServicePort`, `projectRoot`, and `device` so the dusk CLI can find the app.

### Responsive: desktop and mobile are both required

The shell swaps at `lg` (1024px): a sidebar plus content column above it, a bottom
tab bar below. A change to any screen is verified on both sides of that line, since
they are different widget trees. Useful widths: 390 (phone, no sidebar), 768
(tablet portrait, still the mobile shell), 1200, and 1440 or wider.

Resize through CDP `Browser.getWindowForTarget` + `Browser.setWindowBounds`.
**Not** `Emulation.setDeviceMetricsOverride`: Flutter web reads its logical size
from the host element, so that override grows the screenshot canvas while the app
keeps laying out at the old width, and everything renders doubled and clipped.

### Driver behavior worth knowing

- `dusk:tap --ref=eN` is the tap verb; there is no `dusk:click`.
- `dusk:wait` prints a human line rather than JSON. Parse the text.
- If `dusk:snap` returns an empty tree on a web build, `dusk:navigate` returns a
  populated one, so navigate-then-read is the way in.
- `dusk:scroll` may not move a page whose scrollable is owned by the shell rather
  than the content. A real `Input.dispatchMouseEvent type: 'mouseWheel'` does.
- `fsa tinker --eval=...` does not work against a web-server device (dwds answers
  `NoSuchMethodError`). Use CDP `Runtime.evaluate`.

### Traps that produce confident wrong measurements

- An exact-label lookup over the semantics tree resolves to the **sidebar** nav
  item, which carries the same label as the page it opens. Constrain the search to
  the content region or you will measure the sidebar and conclude two pages differ.
- A hardcoded content-region threshold (`x > 300`) is wrong at other widths: at
  1200px the container starts further left, at 390px there is no sidebar at all.
  Derive it from the width under test.
- "The bottom-most content node" matches an aggregate parent whose box spans the
  whole page, so an overlap check reads true on every page including unchanged
  ones. Look at the screenshot.
- **A sibling project's dev server answers on `localhost:8000`.** `API_URL` names
  that port, and `uptizm/backend` was already listening on it, so the app spent
  twenty minutes talking to the wrong API. It presented as **"Invalid
  credentials"** on the login screen, which reads as a bad password rather than a
  wrong backend. `lsof -nP -iTCP:8000 -sTCP:LISTEN` names the process, and its
  `cwd` names the project. Run this repo's API on a free port and override
  `API_URL` for the run rather than editing the tracked `.env` and committing it,
  which is the mistake that produced this note.
- **A `[ref=eN]` belongs to the snapshot that produced it.** After a hot restart
  the tree is rebuilt and the refs move, so replaying a login with the previous
  snapshot's refs types into nothing and the "successful" taps go nowhere. Re-snap
  and read the refs out of that output. On web a restart also drops the session,
  so the path always starts at the login screen again.
- **`gh pr checks --watch` can hang after every check has passed.** A plain
  `gh pr checks <n>` answers immediately with the same table.
- **A dusk action reports that it DISPATCHED, not that the widget received.**
  `dusk:fill` printed a green tick four times onto a field covered by the pinned
  footer, because the row is in the semantics tree and dusk's six actionability
  checks do not include occlusion by another `Stack` layer (Playwright's
  receives-events check is the equivalent). A control that never responds to two
  different input paths is the tell: try the stepper as well as the field, and if
  neither lands, look at a screenshot before debugging the widget.
- **`dusk:scroll --dy` needs a ref that IS a scrollable.** Given a textbox ref it
  answers "Scrolled eN" and moves nothing. `--intoView` is the flag that works;
  reach for it first. Then re-snap: refs belong to the snapshot that produced them,
  so acting on a pre-scroll ref fails in a way that looks identical.
- **A bottom spacer only changes scroll EXTENT, so a screenshot cannot see it.**
  Two captures across a hot restart were byte-identical and the natural conclusion
  ("the capture is stale") was wrong: a viewport scrolled to the top genuinely is
  unchanged. Navigating elsewhere proved the tool fine. Before calling an
  instrument broken, ask whether the change under test could appear in what it
  measures; to check a reservation, scroll the LAST row into view and look at that.
- **`dusk:fill --text=''` does not fire the field's `onChanged`.** Its clear step
  sets the text rather than editing it, so a "user cleared the field" path cannot be
  exercised that way and the row keeps its old state, which reads as a bug in the
  widget. A real backspace does fire it (`WInput` forwards straight to Flutter's
  `TextField`). To test the empty branch, type a value the parser REJECTS but the
  keyboard accepts (`.` or `-`): that fires `onChanged` with something unparseable
  and takes the same path.
- **A screen's `dusk:exceptions` was never clean on the eight screens with a
  footer**, so the check that catches a real render fault had two entries in it by
  default. If a baseline is noisy, fix the noise rather than learning to read past
  it: an instrument with a permanent false positive stops being consulted.

## What counts as evidence

A claim needs the artifact behind it: the `bin/check` summary, the screenshot pair,
the snapshot or the response body. "Should work" and "green locally" are not
evidence, and neither is a passing test that could not have failed. Screenshots and
snapshots go under `.ac/evidence/`.

## Seeing a whole screen, not just its first viewport

`dusk:screenshot` captures the viewport. A product screen is taller than that, so a
plain screenshot shows the top and hides everything you actually changed. Resize the
viewport tall instead of trying to scroll:

```sh
./bin/fsa start --device=chrome --cdp-port=9333
./bin/fsa dusk:resize --width=1500 --height=3400
./bin/fsa dusk:screenshot -o /tmp/screen.jpg
```

Three flags carry the whole thing, and each fails quietly when missing:

- **`--cdp-port` on `start` is mandatory for resizing.** `dusk:resize` drives Chrome
  DevTools Protocol; without the port it reports "CDP not enabled" while
  `dusk:screenshot` still succeeds, so you get a viewport-sized image and no obvious
  error. If the port is taken, pick another: `lsof -ti:9222 | xargs kill -9` clears a
  stale one.
- **`dusk:scroll` needs `--ref`**, the snapshot ref of the scrollable from a prior
  `dusk:snap`, and its magnitude is `--pixels`, not `--amount`. Given only
  `--direction` it prints help and moves nothing, which reads like a no-op.
- **Do not narrow the viewport to test mobile through `/preview`.** The catalog keeps
  its sidebar at every width, so at 430px the content column collapses to roughly
  130px and shows a RenderFlex overflow belonging to the catalog rather than to the
  screen. For a real phone-width check, navigate to the route directly.

This is not optional polish. A single session of skipping it shipped a self-hiding
badge that left a phantom flex gap, a full-width button whose label sat against the
left edge, a navigation link stretched to half a card, and an empty state still
reading "5 adet" and "9 hareket". `flutter analyze` was clean through all four.

## Seeing both widths in one capture

`ResponsiveScreenPreview` stacks the wide arrangement above the 390px frame, so one preview holds
both. A screenshot does NOT hold both by default: `dusk:screenshot` captures the viewport and has
no full-page flag, so the phone half sits below the fold.

```sh
./bin/fsa dusk:resize --width=1400 --height=2200   # tall enough for both halves
./bin/fsa dusk:navigate --route=/preview/<screen>
./bin/fsa dusk:screenshot -o /tmp/<screen>.jpg
./bin/fsa dusk:resize --width=1400 --height=1000   # put it back
```

Restore the height afterwards. A 2200px viewport changes what `MediaQuery` reports, and the next
screen you look at would be laid out against a window no phone or laptop has.
