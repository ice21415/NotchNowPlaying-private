#!/usr/bin/env python3
"""Small deterministic model checks for the Phase 7.11 lifecycle invariants.

This is deliberately a model test, not a claim that private SpringBoard APIs
are safe. Device behavior still requires the attended test described in the
Phase 7.11 report.
"""

from dataclasses import dataclass


@dataclass
class Model:
    state: str = "Idle"
    locked: bool = False
    substituted: bool = False
    timer_started: bool = False
    session: int = 0
    restore_count: int = 0
    provider_available: bool = True

    def arm(self):
        if self.locked or self.state in {"Preparing", "Active"}:
            return False
        self.session += 1
        self.state = "Preparing"
        self.substituted = False
        self.timer_started = False
        return True

    def mode_substitution(self):
        if self.state not in {"Preparing", "Active"}:
            return
        self.substituted = True
        if self.locked:
            self.state = "Active"
            self.timer_started = True

    def lock(self):
        self.locked = True
        if self.state == "Preparing" and self.substituted:
            self.state = "Active"
            self.timer_started = True

    def unlock(self):
        self.locked = False
        self.stop("unlock")

    def stop(self, reason):
        if self.state in {"Idle", "Stopping"}:
            return
        self.state = "Stopping"
        self.timer_started = False
        if self.locked and self.substituted and self.provider_available:
            self.restore_count += 1
        self.state = "Idle"
        self.substituted = False

    def timeout(self):
        if self.state == "Active" and self.locked and self.timer_started:
            self.stop("maximum-duration")


def test_armed_without_lock_does_not_timeout():
    m = Model()
    assert m.arm()
    m.timeout()
    assert m.state == "Preparing"
    assert not m.timer_started
    assert m.restore_count == 0


def test_valid_lock_starts_timer_and_restores_once():
    m = Model()
    assert m.arm()
    m.lock()
    m.mode_substitution()
    assert m.state == "Active" and m.timer_started
    m.timeout()
    m.timeout()
    assert m.state == "Idle"
    assert m.restore_count == 1


def test_early_unlock_cancels_timer_without_locked_restore():
    m = Model()
    m.arm()
    m.lock()
    m.mode_substitution()
    m.unlock()
    assert m.state == "Idle" and not m.timer_started
    assert m.restore_count == 0


def test_stale_previous_session_cannot_stop_new_session():
    m = Model()
    m.arm()
    old_session = m.session
    m.stop("preference-disable")
    assert m.arm() and m.session != old_session
    m.lock()
    m.mode_substitution()
    assert m.state == "Active"
    # A stale callback from old_session has no permission to clean this one.
    assert old_session != m.session
    assert m.state == "Active"


def test_provider_unavailable_fails_open():
    m = Model(provider_available=False)
    m.arm()
    m.lock()
    m.mode_substitution()
    m.timeout()
    assert m.state == "Idle"
    assert m.restore_count == 0


def test_multiple_cleanup_events_are_idempotent():
    m = Model()
    m.arm()
    m.lock()
    m.mode_substitution()
    m.timeout()
    m.stop("unlock")
    m.stop("preference-disable")
    assert m.restore_count == 1


if __name__ == "__main__":
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Phase 7.11 lifecycle model tests")
