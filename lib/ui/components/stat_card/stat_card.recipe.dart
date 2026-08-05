// StatCard shows a single KPI: a small uppercase label, a large value, and an
// optional delta line. No variant axes, so the slot classNames are plain
// functions per the atomic-component recipe contract.

/// Root surface panel.
String statCardRootClassName() =>
    'flex flex-col gap-1 rounded-lg border border-color-border '
    'bg-surface-container px-5 py-4';

/// Label: small, muted, uppercase.
String statCardLabelClassName() =>
    'text-xs font-medium uppercase tracking-wide text-fg-muted';

/// Value: the large headline figure.
String statCardValueClassName() => 'text-2xl font-semibold text-fg';

/// Delta: the optional trailing subtitle.
String statCardDeltaClassName() => 'text-xs text-fg-muted';
