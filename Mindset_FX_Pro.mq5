//+------------------------------------------------------------------+
//| Mindset FX PRO - XAUUSD M1                                       |
//| Trend confirmation: H1 + M15 | Entry: M1                         |
//| Test on a DEMO account before any live use.                      |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "Mindset FX PRO - XAUUSD M1 with H1/M15 trend filters"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Risk and execution settings
input double RiskPercent       = 1.0;    // Risk per trade (% of equity)
input double RiskReward        = 2.0;    // Take-profit distance = SL distance * RR
input ulong  MagicNumber       = 701107;
input int    MaxSpreadPoints   = 100;    // Adjust to your broker's XAUUSD quote
input int    SlippagePoints    = 20;

//--- Strategy settings
input int    TrendFastEMA      = 50;
input int    TrendSlowEMA      = 200;
input int    EntryEMA          = 20;
input int    RSIPeriod         = 14;
input int    ATRPeriod         = 14;
input double ATRStopMultiplier = 1.5;

//--- Indicator handles
int hFastH1   = INVALID_HANDLE;
int hSlowH1   = INVALID_HANDLE;
int hFastM15  = INVALID_HANDLE;
int hSlowM15  = INVALID_HANDLE;
int hEntryM1  = INVALID_HANDLE;
int hRsiM1    = INVALID_HANDLE;
int hAtrM1    = INVALID_HANDLE;

datetime lastM1Bar = 0;

//+------------------------------------------------------------------+
//| Read one indicator value from a completed candle                 |
//+------------------------------------------------------------------+
bool ReadValue(const int handle, const int shift, double &value)
{
   double data[1];
   if(handle == INVALID_HANDLE)
      return false;

   if(CopyBuffer(handle, 0, shift, 1, data) != 1)
      return false;

   value = data[0];
   return (value != EMPTY_VALUE);
}

//+------------------------------------------------------------------+
//| Calculate volume digits from broker volume step                  |
//+------------------------------------------------------------------+
int VolumeDigitsFromStep(const double step)
{
   if(step >= 1.0)  return 0;
   if(step >= 0.1)  return 1;
   if(step >= 0.01) return 2;
   if(step >= 0.001)return 3;
   return 4;
}

//+------------------------------------------------------------------+
//| Calculate volume so estimated stop loss is within risk budget    |
//+------------------------------------------------------------------+
double CalculateRiskVolume(const ENUM_ORDER_TYPE orderType,
                           const double entryPrice,
                           const double stopPrice)
{
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskCash = equity * RiskPercent / 100.0;

   if(riskCash <= 0.0)
      return 0.0;

   double oneLotResult = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0,
                       entryPrice, stopPrice, oneLotResult))
   {
      Print("OrderCalcProfit failed. Error: ", GetLastError());
      return 0.0;
   }

   double lossPerLot = MathAbs(oneLotResult);
   if(lossPerLot <= 0.0)
      return 0.0;

   double rawVolume = riskCash / lossPerLot;

   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || minVolume <= 0.0)
      return 0.0;

   // Round DOWN so volume does not exceed the calculated risk.
   double volume = MathFloor(rawVolume / step) * step;

   // If minimum lot would exceed the risk budget, do not trade.
   if(volume < minVolume)
   {
      Print("Trade skipped: minimum lot is too large for the risk budget.");
      return 0.0;
   }

   volume = MathMin(volume, maxVolume);
   return NormalizeDouble(volume, VolumeDigitsFromStep(step));
}

//+------------------------------------------------------------------+
//| Check whether this symbol already has an open position           |
//+------------------------------------------------------------------+
bool HasOpenPositionOnSymbol()
{
   return PositionSelect(_Symbol);
}

//+------------------------------------------------------------------+
//| Open a market trade                                               |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE orderType, const double atrValue)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(point <= 0.0 || atrValue <= 0.0)
      return;

   double spreadPoints = (tick.ask - tick.bid) / point;
   if(spreadPoints > MaxSpreadPoints)
   {
      Print("Trade skipped: spread too high (", spreadPoints, " points).");
      return;
   }

   double stopDistance = atrValue * ATRStopMultiplier;
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minimumDistance = (double)stopsLevel * point;

   if(stopDistance < minimumDistance)
      stopDistance = minimumDistance + point;

   double entryPrice, stopPrice, takeProfit;
   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = tick.ask;
      stopPrice  = NormalizeDouble(entryPrice - stopDistance, digits);
      takeProfit = NormalizeDouble(entryPrice + stopDistance * RiskReward, digits);
   }
   else
   {
      entryPrice = tick.bid;
      stopPrice  = NormalizeDouble(entryPrice + stopDistance, digits);
      takeProfit = NormalizeDouble(entryPrice - stopDistance * RiskReward, digits);
   }

   double volume = CalculateRiskVolume(orderType, entryPrice, stopPrice);
   if(volume <= 0.0)
      return;

   bool sent = false;
   if(orderType == ORDER_TYPE_BUY)
      sent = trade.Buy(volume, _Symbol, 0.0, stopPrice, takeProfit, "Mindset FX PRO BUY");
   else
      sent = trade.Sell(volume, _Symbol, 0.0, stopPrice, takeProfit, "Mindset FX PRO SELL");

   if(!sent)
   {
      Print("Order failed. Retcode: ", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription());
   }
   else
   {
      Print("Order sent. Volume: ", volume,
            " SL: ", stopPrice, " TP: ", takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAUUSD") < 0)
   {
      Print("Attach this EA to an XAUUSD chart. Current symbol: ", _Symbol);
      return INIT_FAILED;
   }

   if(_Period != PERIOD_M1)
   {
      Print("Attach Mindset FX PRO to the XAUUSD M1 chart.");
      return INIT_FAILED;
   }

   if(RiskPercent <= 0.0 || RiskPercent > 1.0 ||
      RiskReward <= 0.0 || ATRStopMultiplier <= 0.0)
   {
      Print("Invalid inputs. RiskPercent must be > 0 and <= 1.0.");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   hFastH1  = iMA(_Symbol, PERIOD_H1, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowH1  = iMA(_Symbol, PERIOD_H1, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hFastM15 = iMA(_Symbol, PERIOD_M15, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowM15 = iMA(_Symbol, PERIOD_M15, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEntryM1 = iMA(_Symbol, PERIOD_M1, EntryEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRsiM1   = iRSI(_Symbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE);
   hAtrM1   = iATR(_Symbol, PERIOD_M1, ATRPeriod);

   if(hFastH1 == INVALID_HANDLE || hSlowH1 == INVALID_HANDLE ||
      hFastM15 == INVALID_HANDLE || hSlowM15 == INVALID_HANDLE ||
      hEntryM1 == INVALID_HANDLE || hRsiM1 == INVALID_HANDLE ||
      hAtrM1 == INVALID_HANDLE)
   {
      Print("Could not create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   Print("MINDSET FX PRO initialized on ", _Symbol,
         ". H1/M15 trend confirmation, M1 entry.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main strategy: evaluate once when a new M1 candle begins          |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBar == 0 || currentBar == lastM1Bar)
      return;

   lastM1Bar = currentBar;

   // Use only completed candles: shift 1 and shift 2.
   if(Bars(_Symbol, PERIOD_H1) < TrendSlowEMA + 5 ||
      Bars(_Symbol, PERIOD_M15) < TrendSlowEMA + 5 ||
      Bars(_Symbol, PERIOD_M1) < 50)
      return;

   if(HasOpenPositionOnSymbol())
      return;

   double fastH1, slowH1, fastM15, slowM15;
   double emaM1_1, emaM1_2, rsiM1, atrM1;

   if(!ReadValue(hFastH1, 1, fastH1) ||
      !ReadValue(hSlowH1, 1, slowH1) ||
      !ReadValue(hFastM15, 1, fastM15) ||
      !ReadValue(hSlowM15, 1, slowM15) ||
      !ReadValue(hEntryM1, 1, emaM1_1) ||
      !ReadValue(hEntryM1, 2, emaM1_2) ||
      !ReadValue(hRsiM1, 1, rsiM1) ||
      !ReadValue(hAtrM1, 1, atrM1))
      return;

   double closeH1  = iClose(_Symbol, PERIOD_H1, 1);
   double closeM15 = iClose(_Symbol, PERIOD_M15, 1);
   double closeM1_1 = iClose(_Symbol, PERIOD_M1, 1);
   double closeM1_2 = iClose(_Symbol, PERIOD_M1, 2);
   double openM1_1  = iOpen(_Symbol, PERIOD_M1, 1);

   if(closeH1 <= 0.0 || closeM15 <= 0.0 ||
      closeM1_1 <= 0.0 || closeM1_2 <= 0.0)
      return;

   // Higher-timeframe trend alignment.
   bool bullishTrend =
      (fastH1 > slowH1 && closeH1 > fastH1) &&
      (fastM15 > slowM15 && closeM15 > fastM15);

   bool bearishTrend =
      (fastH1 < slowH1 && closeH1 < fastH1) &&
      (fastM15 < slowM15 && closeM15 < fastM15);

   // M1 entry: completed candle crosses EntryEMA with RSI confirmation.
   bool bullishEntry =
      (closeM1_2 <= emaM1_2) &&
      (closeM1_1 > emaM1_1) &&
      (closeM1_1 > openM1_1) &&
      (rsiM1 > 50.0 && rsiM1 < 70.0);

   bool bearishEntry =
      (closeM1_2 >= emaM1_2) &&
      (closeM1_1 < emaM1_1) &&
      (closeM1_1 < openM1_1) &&
      (rsiM1 < 50.0 && rsiM1 > 30.0);

   if(bullishTrend && bullishEntry)
      OpenTrade(ORDER_TYPE_BUY, atrM1);
   else if(bearishTrend && bearishEntry)
      OpenTrade(ORDER_TYPE_SELL, atrM1);
}

//+------------------------------------------------------------------+
//| Release indicator resources                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hFastH1  != INVALID_HANDLE) IndicatorRelease(hFastH1);
   if(hSlowH1  != INVALID_HANDLE) IndicatorRelease(hSlowH1);
   if(hFastM15 != INVALID_HANDLE) IndicatorRelease(hFastM15);
   if(hSlowM15 != INVALID_HANDLE) IndicatorRelease(hSlowM15);
   if(hEntryM1 != INVALID_HANDLE) IndicatorRelease(hEntryM1);
   if(hRsiM1   != INVALID_HANDLE) IndicatorRelease(hRsiM1);
   if(hAtrM1   != INVALID_HANDLE) IndicatorRelease(hAtrM1);

   Print("MINDSET FX PRO stopped. Reason: ", reason);