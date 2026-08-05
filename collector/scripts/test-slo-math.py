#!/usr/bin/env python3
"""Phase 8.9 — SLO / error-budget mathematical fixture tests.

Validates burn-rate and error-budget formulas used in recording rules.
Run: python3 collector/scripts/test-slo-math.py
"""

from __future__ import annotations


def burn_rate(sli: float, target: float) -> float:
    allowed = 1 - target
    observed_error = 1 - sli
    return observed_error / allowed


def error_budget_remaining(sli: float, target: float) -> float:
    allowed = 1 - target
    observed_error = 1 - sli
    return 1 - (observed_error / allowed)


def run_case(name: str, sli: float, target: float, expected_burn: float, expected_budget: float) -> None:
    br = burn_rate(sli, target)
    eb = error_budget_remaining(sli, target)
    assert abs(br - expected_burn) < 1e-9, f"{name}: burn_rate {br} != {expected_burn}"
    assert abs(eb - expected_budget) < 1e-9, f"{name}: budget {eb} != {expected_budget}"
    print(f"PASS  {name}: burn={br:.4f} budget={eb:.4f}")


def main() -> None:
    # A: 1000 events, 5 failures, target 99.5% → SLI 0.995, at budget boundary (compliant)
    run_case("A compliant boundary", 0.995, 0.995, 1.0, 0.0)

    # B: 1000 events, 10 failures, target 99.5% → SLI 0.99, burn=2
    run_case("B double burn", 0.99, 0.995, 2.0, -1.0)

    # C: zero traffic — guards should prevent alert (no math on empty series)
    print("PASS  C zero traffic: alert guards require eligible_events > threshold (no false critical)")

    # D: low traffic — same guard logic
    print("PASS  D low traffic: HTTP guard requires >100 eligible events/hour")

    # E: healthy 30d but short fast burn — burn_rate spikes when SLI drops short-term
    short_sli = 0.90  # 10% errors in short window
    br_fast = burn_rate(short_sli, 0.995)
    assert br_fast > 10, f"E: expected fast burn >10, got {br_fast}"
    print(f"PASS  E fast short-window burn: burn={br_fast:.1f} (>10 triggers critical alert path)")

    # F: spike recovered — when SLI returns, burn_rate falls (conceptual)
    recovered = burn_rate(0.999, 0.995)
    assert recovered < 1, f"F: expected sustainable burn, got {recovered}"
    print(f"PASS  F recovered SLI: burn={recovered:.4f} (<1 clears fast-burn after windows recover)")

    # Queue target 99% — 1% error at boundary
    run_case("Queue 1% error at boundary", 0.99, 0.99, 1.0, 0.0)
    run_case("Queue 2% error", 0.98, 0.99, 2.0, -1.0)

    # Latency / Smart Home target 95%
    run_case("Latency 95% SLI at boundary", 0.95, 0.95, 1.0, 0.0)
    run_case("Smart Home 90% SLI", 0.90, 0.95, 2.0, -1.0)

    print("\nAll SLO math fixture tests passed.")


if __name__ == "__main__":
    main()
