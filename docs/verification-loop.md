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

Two boot failures read as "the app is broken" rather than as a missing service:

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

## What counts as evidence

A claim needs the artifact behind it: the `bin/check` summary, the screenshot pair,
the snapshot or the response body. "Should work" and "green locally" are not
evidence, and neither is a passing test that could not have failed. Screenshots and
snapshots go under `.ac/evidence/`.
