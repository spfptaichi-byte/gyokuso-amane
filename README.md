# 玉操 Gyokuso (Amane Trade Command)

MT5 Expert Advisor that tests one question:
**Can position-size control ("gyoku-sousa") alone turn an entry with no edge into a profitable system?**

- Entry: one trade per day at a fixed server hour. Direction is random (seeded), or previous daily candle trend / reverse.
- Exit: time-based close after N hours (default 24h), plus an emergency stop-loss.
- Sizing: per "term", cumulative pips are tracked. Every `PipsPerStep` pips of term loss adds `LotStep` to the lot. When cumulative pips return to 0 or above, the term ends and the lot resets to `BaseLot`. A `MaxLot` cap is enforced.
- `UseLotControl=false` runs a fixed-lot baseline, so the effect of sizing can be isolated.

Inspired by two Japanese articles on "玉操作" and "レバレッジ操作" (fxfan.club). Those articles claim the method works even with zero-edge entries; this repository exists to verify that claim with long backtests.

## Background
Developed after the KamidamaControl project (separate repo) showed that its entry had almost no edge and that losses were not followed by wins (no mean reversion), so loss-triggered sizing could not help there.

## Layout
- `src/` EA source (UTF-8 with BOM)
- `docs/` verification log

## Status
Experimental. Not a product. No result yet.

## 日本語メモ
神玉コントロールとは別物。記事の「玉操作」をランダムエントリーで検証するための実験EA。
