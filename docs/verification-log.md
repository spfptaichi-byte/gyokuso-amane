# Verification Log — KamidamaV18_1 (Simple edition)

Running record of backtests and what each one taught us. One row per run, newest last.
Common conditions unless noted: XAUUSD M15, initial deposit $10,000, leverage 1:500, "Open prices only" model, default inputs (BaseLot 0.1 / LotStep 0.05 / DollarPerLotAdd 20 / SL preset 0).

Honest summary so far: the lot-management logic now behaves as designed, and the TermStop safety device works. The entry logic (H1 EMA21 direction) shows almost no edge on its own (about +0.5 price-width per trade), so results depend heavily on when the run starts. No adopt/reject decision has been made.

## Run table

| # | Date | EA version | Period | TermStop | Result | Finding |
|---|------|-----------|--------|----------|--------|---------|
| 1 | 11/13 | v18.10 (before fix) | 2019.01 - 2026.10 | OFF | Zero-cut on 2019.05.23 (-$9,943, 17 trades, win rate 29%) | Lot rose about 10x faster than designed: one SL loss of $15 width raised the lot by ~7.5 steps instead of 0.75. Cause: cumulative width was back-calculated from P/L with TICK_VALUE/TICK_SIZE, which the tester returns at 1/10 for XAUUSD. |
| 2 | 11/14 | v18.12 (width measured from entry/exit prices) | 2019.01 - 2026.10 | OFF | Stopped out 2019.11.01 (-$9,987, 63 trades, win rate 30.2%, PF 0.56) | Lot stages now match the design (one step per cumulative $20 width, drops after wins; first trades verified by hand). Failure is now the entry side: avg win ~16 width vs fixed 15 loss at 30% win rate = negative expectancy. |
| 3 | 11/15 | v18.12 | 2025.01 - 2026.10 | OFF | +$149,861 (16x), PF 1.08, win 36.7%, 2,643 trades, balance DD 74.66% | Lot matched design in 2,613 / 2,643 trades (30 off-by-one cases, mostly 01:00 entries; cause not yet investigated). Price-width sum only +1,609 (~+0.6 per trade): profit comes from lots being high during big trends (2025.10, 2026.01-02, 2026.06), not from entry edge. 0.1-lot trades alone: -$1,398. |
| 4 | 11/15 | v18.12 | 2025.01 - 2026.10 | ON 20% | Identical to #3 (all 5,286 deals match, 0 forced closes) | The safety device never fired even at 74.66% DD. |
| 5 | 11/16 | (log review of #1) | - | - | Root cause confirmed | Tester log of the v18.10 run shows profit -150 for width -150.0 at 0.1 lot, i.e. conversion factor 10 instead of 100. TermStop loss was estimated as width x lot x factor, so the deepest term (~$26,052) never reached the $28,956 threshold. Whether real brokers show the same factor is unverified. |
| 6 | 11/16 | v18.13 (loss = this EA's realized + floating P/L) | 2025.01 - 2026.10 | ON 20% | +$5,582, PF 1.01, win 36.4%, 2,674 trades, balance DD 79.70% | 29 forced closes, and the next entry returned to 0.1 lot all 29 times. Max lot 0.85 (vs 2.6 in #3). The fix works; but cutting terms at 20% removes the recovery that produced #3's profit, and DD did not improve. |
| 7 | 11/16 | v18.13 | 2019.01 - 2026.10 | ON 20% | +$22,806 (final $32,806), PF 1.03, win 37.6%, 3,654 trades, balance DD 63.03%, min balance $3,636 | 51 forced closes, all followed by a 0.1-lot entry. Survives 2019 (old versions blew up in 2019). Yearly P/L: 2019 -6,364 / 2020 +3,473 / 2021 -383 / 2022 -300 / 2023 +5,193 / 2024 +547 / 2025 +10,845 / 2026 +9,794. 2019-2022 total is negative; profit concentrates in 2025.12 - 2026.08, and 2026.03 / 05 / 09 / 10 gave back about $57k of the $80k peak. |

## Changes made because of these runs

- v18.12: cumulative price-width is measured directly from entry/exit prices (no TICK_VALUE dependency). Entry, SL and trail untouched.
- v18.13: TermStop loss = -(term realized P/L + this EA's floating P/L, filtered by MagicNumber); deals that arrive after a forced close are not added to the new term. Tool: `tools/Analyze-BTReport.ps1` for report analysis.

## Open items / next experiments

- Sweep TermStopPct (10 / 15 / 20 / 30 / 40 / 50) on the 7-year run.
- Compare Trend and Swing editions under the same conditions.
- Investigate the 30 off-by-one lot cases at 01:00 entries.
- Realized P/L in v18.13 uses DEAL_PROFIT only (closed-deal swap/commission not included); review after more runs.
- Check whether the tick-value factor of 10 also appears on real broker accounts.
- Results depend strongly on the start date (compare #3/#6 vs #7 for 2025-26), so any product page would need start-date-by-start-date disclosure.
