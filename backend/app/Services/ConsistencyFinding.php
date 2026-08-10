<?php

namespace App\Services;

/**
 * One thing the database says that should not be true.
 *
 * ### Why a finding carries an expected and an actual rather than a message
 *
 * The command renders it, a Filament panel will list it, and an alert will count it. A pre-rendered
 * sentence would force the second and third of those to parse the first, and the two numbers are the
 * whole content of most findings: "10.000 in the ledger, 999.000 in the projection" is the diagnosis.
 *
 * [repairable] is a property of the CHECK rather than of the row. A drifted projection can be
 * rebuilt from the ledger, because the ledger wins by definition (invariant 1). A product holding
 * both lots and serials cannot be repaired by any rule this code could apply: which of the two
 * numbers is the real quantity is a question about a shelf, and only a person can look at it.
 */
final readonly class ConsistencyFinding
{
    /**
     * @param  string  $check  the slug, stable enough to alert on
     * @param  int|null  $invariant  the numbered invariant in `data-model.md`, or null when the rule is a decision
     * @param  string  $subject  what is wrong, in a form a person can search for
     * @param  array<string, string|null>  $context  the identifiers a repair needs
     */
    public function __construct(
        public string $check,
        public ?int $invariant,
        public ?string $teamId,
        public string $subject,
        public string $expected,
        public string $actual,
        public bool $repairable,
        public array $context = [],
    ) {}

    /**
     * The one-line form, for the console and for a log.
     */
    public function describe(): string
    {
        $rule = $this->invariant === null ? $this->check : 'invariant '.$this->invariant;

        return sprintf(
            '%s [%s] %s: expected %s, found %s',
            $this->repairable ? 'REPAIRABLE' : 'MANUAL    ',
            $rule,
            $this->subject,
            $this->expected,
            $this->actual,
        );
    }
}
