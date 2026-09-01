<?php

namespace Tests\Concerns;

use Symfony\Component\Process\Process;

/**
 * Chrome and poppler, or a decision about their absence.
 *
 * ### Why skipping is right on a laptop and wrong in CI
 *
 * These are the only tests that make D71's guarantees real. The millimetre claim is checked by
 * measuring a rendered page and the font claim by extracting its text and reading its embedded font
 * list, so both need a browser and `pdftotext`. On a machine without them a skip is the honest answer.
 *
 * In CI it is the opposite: a skip and a pass look identical in a summary, so a runner that loses
 * Chrome would report a green build with the font guarantee unverified, which is exactly the failure
 * the tests exist to prevent. `LABEL_RENDER_REQUIRED=1` in the workflow turns the skip into a failure.
 *
 * ### Why this is a trait rather than a method in each test
 *
 * Two copies, and they drifted within one sitting: the same helper existed in `LabelRenderTest` and
 * `LabelEndpointTest` with different skip messages, which is a small thing that is also how a strict
 * mode ends up applying to one of them.
 */
trait NeedsRenderToolchain
{
    /**
     * @param  string  ...$binaries  Defaults to the pair every render test needs.
     */
    protected function requireRenderToolchain(string ...$binaries): void
    {
        $binaries = $binaries ?: ['pdftotext', 'pdfinfo'];

        $missing = [];

        foreach ($binaries as $binary) {
            $probe = new Process(['which', $binary]);
            $probe->run();

            if (! $probe->isSuccessful()) {
                $missing[] = $binary;
            }
        }

        if (! is_file((string) config('labels.chrome_path'))) {
            $missing[] = 'chrome (CHROME_PATH)';
        }

        if ($missing === []) {
            return;
        }

        $message = 'the render toolchain is incomplete (missing: '.implode(', ', $missing).')';

        if (filter_var(env('LABEL_RENDER_REQUIRED', false), FILTER_VALIDATE_BOOLEAN)) {
            $this->fail(ucfirst($message).', and it is required in this environment.');
        }

        $this->markTestSkipped(ucfirst($message).'.');
    }
}
