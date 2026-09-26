// The decision behind an alert notification, kept out of main.qml so it can be
// tested without a Plasma session (harness/tst_alerts.qml).
//
// The strip's colors follow the value at every tick; a notification reports a
// *crossing* instead. An alert that enters a worse state is announced — normal
// → amber → red — and nothing else is:
//
//   - a value that sits over its threshold for an hour is announced once,
//     because the second check sees the same tier as the first;
//   - a value that flaps across the threshold is announced at most once per
//     cooldown, because `sentAt` remembers the last announcement;
//   - an escalation to red is always announced, cooldown or not: the alert
//     getting worse is news even if the amber state was just announced;
//   - a tier that arrives with no history behind it — the first check after a
//     reload, or a tier that moved because the threshold was edited in the
//     settings page — is a baseline, not a crossing.
//
// The state kept per alert, and returned to be stored:
//
//   tier       the tier the last check saw
//   warn/crit  the thresholds that tier was computed with
//   announced  the worst tier announced so far
//   sentAt     when it was announced

// `state` is the alert's stored record, undefined the first time. `reading` is
// { tier, warn, crit } as the alert is now. `options` is
// { armed, enabled, now, cooldownMs }: whether the warm-up is over, whether the
// user asked for this alert, the current time and the repeat floor.
function step(state, reading, options) {
    const known = state !== undefined && state !== null
                  && state.warn === reading.warn && state.crit === reading.crit;
    const crossed = known && reading.tier > state.tier;
    const escalated = crossed && reading.tier > state.announced;
    const cooled = crossed && (options.now - state.sentAt) >= options.cooldownMs;
    const send = crossed && options.armed && options.enabled && (escalated || cooled);

    return {
        send: send,
        state: {
            tier: reading.tier,
            warn: reading.warn,
            crit: reading.crit,
            announced: send ? reading.tier : (known ? state.announced : 0),
            sentAt: send ? options.now : (known ? state.sentAt : 0)
        }
    };
}

// A switch turned on asks about the state of things now, so a value that is
// already in an alert state is announced once at that moment — the one case
// where an announcement is not a crossing. A switch turned off is silent.
function switchedOn(reading, options) {
    const send = options.armed && options.enabled && reading.tier > 0;

    return {
        send: send,
        state: {
            tier: reading.tier,
            warn: reading.warn,
            crit: reading.crit,
            announced: send ? reading.tier : 0,
            sentAt: send ? options.now : 0
        }
    };
}

// The warm-up baseline: what a value is doing, with nothing announced. The
// daemon reports a placeholder 0 to every new subscriber and pushes the real
// value only one updateRateLimit later, so the first check of a fresh applet is
// a baseline — otherwise a reload at login would announce every value that
// happens to be over its threshold.
function baseline(reading) {
    return { tier: reading.tier, warn: reading.warn, crit: reading.crit, announced: 0, sentAt: 0 };
}
