//+------------------------------------------------------------------+
//| Gyokuso_Amane_v0_10.mq5                                          |
//| 玉操(ぎょくそう) 実験版:1日1回エントリー+時間決済+玉操作         |
//| 元ネタ:fxfan.club 玉操作(?p=4230)/レバレッジ操作(?p=37519)     |
//| 目的:「エントリーに優位性がなくても、玉操作で勝てるか」を検証   |
//| 神玉コントロールとは別物。売買の検証用で、商品版ではない          |
//+------------------------------------------------------------------+
#property copyright "AMANE TRADE COMMAND"
#property version   "0.10"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_ENTRY_MODE
{
   ENTRY_RANDOM   = 0, // ランダム(記事に一番近い)
   ENTRY_DAY_TREND= 1, // 前日の日足の向きに順張り
   ENTRY_DAY_REV  = 2  // 前日の日足の向きに逆張り
};

input group "=== エントリー ==="
input ENUM_ENTRY_MODE EntryMode   = ENTRY_RANDOM; // 方向の決め方
input int    RandomSeed           = 1;            // 乱数の種(ランダム時。1,2,3…で回し比べる)
input int    EntryHour            = 2;            // エントリー時刻(サーバー時間の時。0時台はスプレッドが広いので避ける)
input int    HoldHours            = 24;           // 保有時間(この時間がたったら決済)

input group "=== 緊急SL ==="
input double EmergencySL_Pips     = 150;          // 緊急SL(pips)。0で無し

input group "=== 玉操作(ロット管理) ==="
input bool   UseLotControl        = true;         // false=ロット固定(BaseLotのまま)
input double BaseLot              = 0.10;         // 基本ロット
input double LotStep              = 0.05;         // 1段あたりの増加
input double PipsPerStep          = 20;           // ターム累積がこのpips負けるごとに1段上げる
input double MaxLot               = 2.00;         // ロットの上限(安全のため)

input group "=== 共通 ==="
input long   MagicNumber          = 20261117;
input int    Slippage             = 30;

CTrade trade;
double   g_pip        = 0;     // 1pipの価格幅
double   g_termPips   = 0;     // 今のタームの累積pips(0以上でリセット)
int      g_termNum    = 1;
int      g_lastEntryDay = -1;  // 同じ日に2回入らないため
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

int DecideDirection()
{
   if(EntryMode == ENTRY_RANDOM) return (MathRand() % 2 == 0) ? 1 : -1;
   double o = iOpen(_Symbol, PERIOD_D1, 1), c = iClose(_Symbol, PERIOD_D1, 1);
   int d = (c >= o) ? 1 : -1;
   return (EntryMode == ENTRY_DAY_TREND) ? d : -d;
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
   PrintFormat("玉操 v0.10 起動 %s pip=%.5f mode=%d seed=%d 玉操作=%s 段=%.0fpips 上限=%.2f",
               _Symbol, g_pip, (int)EntryMode, RandomSeed, UseLotControl ? "ON" : "OFF(固定)", PipsPerStep, MaxLot);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("通算 %d回 勝率%.1f%% 合計%.1fpips 平均%.2fpips",
               g_trades, g_trades > 0 ? 100.0 * g_wins / g_trades : 0, g_sumPips, g_trades > 0 ? g_sumPips / g_trades : 0);
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
   if(t.hour != EntryHour || t.day_of_year == g_lastEntryDay) return;
   if(t.day_of_week == 0 || t.day_of_week == 6) return;

   int    dir = DecideDirection();
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

   Comment(StringFormat("玉操 v0.10\nターム%d 累積%.1fpips\nロット%.2f\n通算%d回 合計%.1fpips",
                        g_termNum, g_termPips, lot, g_trades, g_sumPips));
}
//+------------------------------------------------------------------+
