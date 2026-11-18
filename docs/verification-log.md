# Verification Log - Gyokuso

Common conditions unless noted: M15 chart, 2019.01.01 - 2026.10.31, $10,000, leverage 1:500, Open prices only, MetaQuotes-Demo.
Entry: random direction (RandomSeed=1), one trade per day at server 02:00, time exit after 24h, emergency SL 150 pips.
Check order: (1) fixed lot first - random entry should lose about the spread per trade; (2) then lot control ON with the same seed, so entries are identical and the difference is the effect of sizing alone.

| # | Date | Version | Symbol | Lot control | Result | Finding |
|---|------|---------|--------|-------------|--------|---------|
| 1 | 11/17 | v0.10 | EURUSD | OFF (0.1 fixed) | -$399, 1,648 trades, win 50.1%, -0.12 pips/trade, DD 17.9% | Baseline behaves as expected for a random entry: about zero minus spread. |
| 2 | 11/17 | v0.10 | EURUSD | ON, +0.05 per 20 pips, cap 2.0 | Ruined 2021.07.01 (-$9,920) after peaking at $17,616 in 2020.10 | 506 of 522 trades above base lot, 79 at the 2.0 cap. A random walk rarely returns to the term start, so terms never close. This setting was about 25x more aggressive than the article (+250% per 100 pips vs +10%). |
| 3 | 11/17 | v0.11 | EURUSD | ON, +0.01 per 100 pips (article-2 strength) | +$7, completed, DD 26.3%, max lot 0.29 | Slightly better than #1 on the same entries, but likely luck of seed 1 (loss-then-win bias of about 2 pips is within noise). |
| 4 | 11/17 | v0.11 | USDJPY | OFF | -$3,782, 1,707 trades, -2.92 pips/trade, DD 46.7%, 107 SL hits | Random entry loses far more than EURUSD: wider spread at 02:00 server time plus large per-trade variance (sd 72 pips). |
| 5 | 11/17 | v0.11 | USDJPY | ON (article-2) | Ruined 2022.11.03 | The 2022 yen trend hit the emergency SL repeatedly while lots were raised. Next trade after a loss averaged -6.9 pips. |
| 6 | 11/17 | v0.11 | GBPJPY | OFF | -$7,711, 1,779 trades, -5.45 pips/trade, DD 82.7%, 233 SL hits | Highest cost and variance of the three pairs. |
| 7 | 11/17 | v0.11 | GBPJPY | ON (article-2) | Ruined 2021.07.20, never above starting balance | Same pattern as #5. |

## Conclusion so far
Lot control does not create an edge. It amplifies whatever the entry already has: near-zero entries can drift either way (#3), negative entries are ruined faster (#5, #7). The articles' claim appears to describe a lucky path of a near-zero-expectancy entry.

## Next
Find entries with positive expectancy at fixed lot, and with losses tending to be followed by wins, then add lot control. Evaluate at fixed lot first: mean pips per trade and mean of the trade after a loss vs after a win.
