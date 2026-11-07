Mindset_FX_Pro.mq5

#property strict
#property version "2.00"
#property description "MINDSET FX PRO"

#include <Trade/Trade.mqh>

CTrade trade;

input double RiskPercent = 1.0;
input double RiskReward = 2.0;

input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;
input ENUM_TIMEFRAMES ConfirmTF = PERIOD_M15;
input ENUM_TIMEFRAMES EntryTF = PERIOD_M5;

int OnInit()
{
   Print("MINDSET FX PRO est initialise.");
   Print("Risque par trade : ", RiskPercent, "%");
   Print("Trading automatique active.");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   // La strategie sera ajoutee ici.
}

void OnDeinit(const int reason)
{
   Print("MINDSET FX PRO arrete.");
}
