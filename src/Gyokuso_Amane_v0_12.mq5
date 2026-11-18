//+------------------------------------------------------------------+
//| Gyokuso_Amane_v0_12.mq5                                          |
//| 玉操(ぎょくそう) 実験版:1日1回エントリー+時間決済+玉操作         |
//| 元ネタ:fxfan.club 玉操作(?p=4230)/レバレッジ操作(?p=37519)     |
//| 目的:「エントリーに優位性がなくても、玉操作で勝てるか」を検証   |
//| 神玉コントロールとは別物。売買の検証用で、商品版ではない          |
//+------------------------------------------------------------------+
#property copyright "AMANE TRADE COMMAND"
#property version   "0.12"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_ENTRY_MODE
{
   ENTRY_RANDOM   = 0, // ランダム(記事に一番近い)
   ENTRY_DAY_TREND= 1, // 前日の日足の向きに順張り
   ENTRY_DAY_REV  = 2, // 前日の日足の向きに逆張り
   ENTRY_ASIA_BREAK = 3, // 順張り:アジア時間のレンジを抜けた方向(EntryHourから窓の時間内)
   ENTRY_STREAK_REV = 4, // 逆張り:日足がN本連続で同じ色なら反対へ
   ENTRY_RSI2_PULL  = 5  // 順張りの押し目:日足SMA200の上でRSI(2)が低い→買い/下で高い→売り
};

input group "=== エントリー ==="
input ENUM_ENTRY_MODE EntryMode   = ENTRY_RANDOM; // 方向の決め方
input int    RandomSeed           = 1;            // 乱数の種(ランダム時。1,2,3…で回し比べる)
input int    EntryHour            = 2;            // エントリー時刻(サーバー時間の時。0時台はスプレッドが広いので避ける)
input int    HoldHours            = 24;           // 保有時間(この時間がたったら決済)
input int    AsiaStartHour        = 0;            // [3]レンジを測り始める時刻(サーバー時間)
input int    BreakWindowHours     = 6;            // [3]EntryHourから何時間ブレイクを待つか
input int    StreakDays           = 3;            // [4]何本連続で同じ色なら逆張りするか
input int    TrendSMA             = 200;          // [5]日足のトレンド判定SMA
input double RSI2_Low             = 10;           // [5]これ未満で買い(SMAの上のとき)
input double RSI2_High            = 90;           // [5]これより上で売り(SMAの下のとき)

input group "=== 緊急SL ==="
input double EmergencySL_Pips     = 150;          // 緊急SL(pips)。0で無し

input group "=== 玉操作(ロット管理) ==="
input bool   UseLotControl        = true;         // false=ロット固定(BaseLotのまま)
input double BaseLot              = 0.10;         // 基本ロット
input double LotStep              = 0.05;         // 1段あたりの増加
input double PipsPerStep          = 20;           // ターム累積がこのpips負けるごとに1段上げる
input double MaxLot               = 2.00;         // ロットの上限(安全のため)
input bool   ResetMonthly         = false;        // true=月が替わったらタームを強制リセット(記事1の方式)

input group "=== 共通 ==="
input long   MagicNumber          = 20261117;
input int    Slippage             = 30;

CTrade trade;
double   g_pip        = 0;     // 1pipの価格幅
double   g_termPips   = 0;     // 今のタームの累積pips(0以上でリセット)
int      g_termNum    = 1;
int      g_lastEntryDay = -1;  // 同じ日に2回入らないため
int      g_termMonth  = -1;    // 月リセット用
int      g_monthResets = 0;
int      g_hSMA = INVALID_HANDLE, g_hRSI = INVALID_HANDLE;
int      g_skipDays = 0;      // 条件が合わず見送った日数
bool     g_hadPos     = false;
ulong    g_posTicket  = 0;
double   g_openPrice  = 0;
int      g_dir        = 0;     // 1=買い, -1=売り
datetime g_openTime   = 0;
double   g_openLot    = 0;

// 通算(ロット固定と比べるための記録)
int      g_trades = 0, g_wins = 0;
double   g_sumPips = 0;

//+------------------------------------------------------------------+
double PipSize()
{
   int    dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(dg == 5 || dg == 3) return pt * 10;
   if(dg == 2 && (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)) return pt * 10; // ゴールドは0.1を1pipとする
   return pt;
}

double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step + 1e-9) * step;
   return MathMax(mn, MathMin(mx, lot));
}

double CurrentLot()
{
   if(!UseLotControl) return NormLot(BaseLot);
   int steps = 0;
   if(g_termPips < 0 && PipsPerStep > 0) steps = (int)MathFloor(-g_termPips / PipsPerStep);
   return NormLot(MathMin(MaxLot, BaseLot + LotStep * steps));
}

bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      { g_posTicket = t; return true; }
   }
   return false;
}

double Buf(int h, int shift)
{
   double b[1];
   if(h == INVALID_HANDLE || CopyBuffer(h, 0, shift, 1, b) != 1) return EMPTY_VALUE;
   return b[0];
}

// 戻り値:1=買い、-1=売り、0=今日は見送り
int DecideDirection()
{
   if(EntryMode == ENTRY_RANDOM) return (MathRand() % 2 == 0) ? 1 : -1;

   if(EntryMode == ENTRY_DAY_TREND || EntryMode == ENTRY_DAY_REV)
   {
      double o = iOpen(_Symbol, PERIOD_D1, 1), c = iClose(_Symbol, PERIOD_D1, 1);
      int d = (c >= o) ? 1 : -1;
      return (EntryMode == ENTRY_DAY_TREND) ? d : -d;
   }

   if(EntryMode == ENTRY_STREAK_REV)
   {
      int up = 0, dn = 0;
      for(int i = 1; i <= StreakDays; i++)
      {
         double o = iOpen(_Symbol, PERIOD_D1, i), c = iClose(_Symbol, PERIOD_D1, i);
         if(c > o) up++; else if(c < o) dn++;
      }
      if(up == StreakDays) return -1;
      if(dn == StreakDays) return 1;
      return 0;
   }

   if(EntryMode == ENTRY_RSI2_PULL)
   {
      double sma = Buf(g_hSMA, 1), rsi = Buf(g_hRSI, 1), c = iClose(_Symbol, PERIOD_D1, 1);
      if(sma == EMPTY_VALUE || rsi == EMPTY_VALUE) return 0;
      if(c > sma && rsi < RSI2_Low)  return 1;
      if(c < sma && rsi > RSI2_High) return -1;
      return 0;
   }

   if(EntryMode == ENTRY_ASIA_BREAK)
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(), t);
      datetime d0 = TimeCurrent() - (t.hour * 3600 + t.min * 60 + t.sec);
      int s1 = iBarShift(_Symbol, PERIOD_M15, d0 + AsiaStartHour * 3600);
      int s2 = iBarShift(_Symbol, PERIOD_M15, d0 + EntryHour * 3600);
      int cnt = s1 - s2;
      if(s1 < 0 || s2 < 0 || cnt <= 0) return 0;
      double hi = iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, cnt, s2 + 1));
      double lo = iLow (_Symbol, PERIOD_M15, iLowest (_Symbol, PERIOD_M15, MODE_LOW,  cnt, s2 + 1));
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > hi) return 1;
      if(bid < lo) return -1;
      return 0;
   }
   return 0;
}

// 決済された取引の価格を履歴から取る(SLで閉じた場合も拾う)
double LastClosePrice()
{
   if(!HistorySelect(g_openTime, TimeCurrent() + 60)) return 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      return HistoryDealGetDouble(d, DEAL_PRICE);
   }
   return 0;
}

void OnClosed()
{
   double cp = LastClosePrice();
   if(cp <= 0) { Print("決済価格が取れませんでした"); return; }
   double pips = (cp - g_openPrice) * g_dir / g_pip;
   g_trades++; g_sumPips += pips; if(pips > 0) g_wins++;
   g_termPips += pips;
   string note = "";
   if(g_termPips >= 0) { note = StringFormat(" → ターム%d終了", g_termNum); g_termNum++; g_termPips = 0; }
   PrintFormat("決済 %s lot:%.2f pips:%.1f ターム累積:%.1f 次lot:%.2f%s",
               g_dir > 0 ? "買" : "売", g_openLot, pips, g_termPips, CurrentLot(), note);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_pip = PipSize();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   MathSrand(RandomSeed);
   if(EntryMode == ENTRY_RSI2_PULL)
   {
      g_hSMA = iMA(_Symbol, PERIOD_D1, TrendSMA, 0, MODE_SMA, PRICE_CLOSE);
      g_hRSI = iRSI(_Symbol, PERIOD_D1, 2, PRICE_CLOSE);
      if(g_hSMA == INVALID_HANDLE || g_hRSI == INVALID_HANDLE) { Print("インジケーターを作れませんでした"); return INIT_FAILED; }
   }
   PrintFormat("玉操 v0.12 起動 %s pip=%.5f mode=%d seed=%d 玉操作=%s 段=%.0fpips 増分=%.2f 上限=%.2f 月リセット=%s",
               _Symbol, g_pip, (int)EntryMode, RandomSeed, UseLotControl ? "ON" : "OFF(固定)", PipsPerStep, LotStep, MaxLot, ResetMonthly ? "ON" : "OFF");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("通算 %d回 勝率%.1f%% 合計%.1fpips 平均%.2fpips 月リセット%d回 見送り%d日",
               g_trades, g_trades > 0 ? 100.0 * g_wins / g_trades : 0, g_sumPips, g_trades > 0 ? g_sumPips / g_trades : 0, g_monthResets, g_skipDays);
   Comment("");
}

void OnTick()
{
   bool has = HasPosition();

   // 1) ポジションが消えた(時間決済 or 緊急SL)→ 記録
   if(g_hadPos && !has) { OnClosed(); g_hadPos = false; }

   // 2) 保有中:時間がたったら決済
   if(has)
   {
      if(TimeCurrent() - g_openTime >= (long)HoldHours * 3600)
         trade.PositionClose(g_posTicket);
      return;
   }

   // 3) エントリー:1日1回、決めた時刻
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);

   // 月リセット(ポジションがない時だけ)
   if(ResetMonthly)
   {
      if(g_termMonth < 0) g_termMonth = t.mon;
      else if(t.mon != g_termMonth)
      {
         if(g_termPips < 0)
         {
            PrintFormat("月替わりリセット ターム%d 累積%.1fpipsで打ち切り", g_termNum, g_termPips);
            g_termNum++; g_monthResets++;
         }
         g_termPips = 0; g_termMonth = t.mon;
      }
   }
   if(t.day_of_year == g_lastEntryDay) return;
   if(t.day_of_week == 0 || t.day_of_week == 6) return;

   bool windowMode = (EntryMode == ENTRY_ASIA_BREAK);
   if(!windowMode && t.hour != EntryHour) return;
   if(windowMode && (t.hour < EntryHour || t.hour >= EntryHour + BreakWindowHours))
   {
      if(t.hour >= EntryHour + BreakWindowHours) { g_lastEntryDay = t.day_of_year; g_skipDays++; }
      return;
   }

   int dir = DecideDirection();
   if(dir == 0)
   {
      if(!windowMode) { g_lastEntryDay = t.day_of_year; g_skipDays++; }   // 窓モードは時間内なら待ち続ける
      return;
   }

   double lot = CurrentLot();
   double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;
   if(EmergencySL_Pips > 0) sl = NormalizeDouble(price - dir * EmergencySL_Pips * g_pip, _Digits);

   bool ok = dir > 0 ? trade.Buy(lot, _Symbol, 0, sl, 0, "Gyokuso")
                     : trade.Sell(lot, _Symbol, 0, sl, 0, "Gyokuso");
   g_lastEntryDay = t.day_of_year;   // 失敗しても同じ日は入り直さない
   if(!ok) { PrintFormat("注文失敗 %s", trade.ResultRetcodeDescription()); return; }

   g_hadPos    = true;
   g_dir       = dir;
   g_openPrice = trade.ResultPrice();
   g_openTime  = TimeCurrent();
   g_openLot   = lot;

   Comment(StringFormat("玉操 v0.12\nターム%d 累積%.1fpips\nロット%.2f\n通算%d回 合計%.1fpips",
                        g_termNum, g_termPips, lot, g_trades, g_sumPips));
}
//+------------------------------------------------------------------+
