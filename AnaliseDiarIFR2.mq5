//+------------------------------------------------------------------+
//|                                              AnaliseDiarIFR2.mq5 |
//|                                              Copyright 2016, EBM |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, EBM"
#property link      "https://www.mql5.com"
#property version   "1.00"
//--- input parameters
input int      StopLoss=30;      // Stop Loss
input int      TakeProfit=100;   // Take Profit
input int      ADX_Period=8;     // ADX Period
input int      MA_Period=8;      // Moving Average Period
input int      EA_Magic=12345;   // EA Magic Number
input double   Adx_Min=22.0;     // Minimum ADX Value
input double   Lot=0.1;          // Lots to Trade

enum Creation
  {
   Call_iRSI,              // use iRSI
   Call_IndicatorCreate    // use IndicatorCreate
  };
//--- input parameters
input Creation             type=Call_iRSI;               // type of the function 
input int                  ma_period=2;                 // period of averaging
input ENUM_APPLIED_PRICE   applied_price=PRICE_CLOSE;    // type of price
input string               symbol=" ";                   // symbol 
input ENUM_TIMEFRAMES      period=PERIOD_CURRENT;        // timeframe
//--- indicator buffer
double         iRSIBuffer[];
//--- variable for storing the handle of the iRSI indicator
int    handle;
string name;
string short_name;
int    bars_calculated=0;


datetime MyTime0;


int adxHandle; // handle for our ADX indicator
int maHandle;  // handle for our Moving Average indicator
double plsDI[],minDI[],adxVal[]; // Dynamic arrays to hold the values of +DI, -DI and ADX values for each bars
double maVal[]; // Dynamic array to hold the values of Moving Average for each bars
double p_close; // Variable to store the close value of a bar
int STP, TKP;   // To be used for Stop Loss & Take Profit values

bool Buy_opened=false;  // variable to hold the result of Buy opened position
bool Sell_opened=false; // variable to hold the result of Sell opened position
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int handleFile;
string filename = "rsi_mt5.csv";

int OnInit()
  {
  
//---
  //--- assignment of array to indicator buffer
   SetIndexBuffer(0,iRSIBuffer,INDICATOR_DATA);
    ArrayGetAsSeries(iRSIBuffer);
//--- determine the symbol the indicator is drawn for
   name=_Symbol;
//--- delete spaces to the right and to the left
   StringTrimRight(name);
   StringTrimLeft(name);
//--- if it results in zero length of the 'name' string
  
//--- create handle of the indicator
   if(type==Call_iRSI)
      handle=iRSI(name,period,ma_period,applied_price);
   else
     {
      //--- fill the structure with parameters of the indicator     
      MqlParam pars[2];
      //--- period of moving average
      pars[0].type=TYPE_INT;
      pars[0].integer_value=ma_period;
      //--- limit of the step value that can be used for calculations
      pars[1].type=TYPE_INT;
      pars[1].integer_value=applied_price;
      handle=IndicatorCreate(name,period,IND_RSI,2,pars);
     }
//--- if the handle is not created
   if(handle==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code
      PrintFormat("Failed to create handle of the iRSI indicator for the symbol %s/%s, error code %d",
                  name,
                  EnumToString(period),
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
     }
//--- show the symbol/timeframe the Relative Strength Index indicator is calculated for
   short_name=StringFormat("iRSI(%s/%s, %d, %d)",name,EnumToString(period),
                           ma_period,applied_price);
   IndicatorSetString(INDICATOR_SHORTNAME,short_name);
//--- normal initialization of the indicator

// Escreve em arquivo  
   FileDelete(filename);
   handleFile=FileOpen(filename,FILE_CSV|FILE_READ|FILE_WRITE,',');
   if(handleFile<1)
   {
      Comment("File data1.csv not found, the last error is ", GetLastError());
      return(false);
   }
   else
   {
      Comment("Ok");
      FileWrite(handleFile, "Ativo", "Data","Aber","Alta", "Baixa", "Fech", "Vol","Aber (ant)","Alta (ant)", "Baixa (ant)", "Fech (ant)", "Vol (ant)", "RSI", "RSI (ant)", "Alvo");
      Comment("1");
   }


   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   Comment("");
   FileClose(handleFile);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
 static datetime Old_Time;
   datetime New_Time[1];
   bool IsNewBar=false;
   
    MqlTick last_tick;
//---
   if(SymbolInfoTick(Symbol(),last_tick))
     {
      Print(last_tick.time,": Bid = ",last_tick.bid,
            " Ask = ",last_tick.ask,"  Volume = ",last_tick.volume);
     }
  MqlDateTime mdate;
  TimeToStruct(last_tick.time, mdate);   
  // Trabalhando com ifr-2, consideraremos apenas cotações no final do pregão, após 17:30  
  if (mdate.hour < 17) {
     return;
  } 
  if (mdate.min < 50) {
     return;
  }
// copying the last bar time to the element New_Time[0]
   int copied=CopyTime(_Symbol,_Period,0,1,New_Time);
   if(copied>0) // ok, the data has been copied successfully
     {
     // if(Old_Time!=New_Time[0]) // if old time isn't equal to new bar time
       // {
         IsNewBar=true;   // if it isn't a first call, the new bar has appeared
        // if(MQL5InfoInteger(MQL5_DEBUGGING)) Print("We have new bar here ",New_Time[0]," old time was ",Old_Time);
         Old_Time=New_Time[0];            // saving bar time
        //}
     }
   else
     {
      Alert("Error in copying historical times data, error =",GetLastError());
      ResetLastError();
      return;
     }

//--- EA should only check for new trade if we have a new bar
   if(IsNewBar==false)
     {
      return;
     }
   
   //--- Define some MQL5 Structures we will use for our trade
   MqlTick latest_price;      // To be used for getting recent/latest price quotes
   MqlTradeRequest mrequest;  // To be used for sending our trade requests
   MqlTradeResult mresult;    // To be used to get our trade results
   MqlRates mrate[];          // To be used to store the prices, volumes and spread of each bar
   ZeroMemory(mrequest);      // Initialization of mrequest structure
   
   // the rates arrays
   ArraySetAsSeries(mrate,true);
// the ADX DI+values array
   ArraySetAsSeries(plsDI,true);
// the ADX DI-values array
   ArraySetAsSeries(minDI,true);
// the ADX values arrays
   ArraySetAsSeries(adxVal,true);
// the MA-8 values arrays
   ArraySetAsSeries(maVal,true);


//--- Get the last price quote using the MQL5 MqlTick Structure
   if(!SymbolInfoTick(_Symbol,latest_price))
     {
      Alert("Error getting the latest price quote - error:",GetLastError(),"!!");
      return;
     }

//--- Get the details of the latest 3 bars
   if(CopyRates(_Symbol,_Period,0,3,mrate)<0)
     {
      Alert("Error copying rates/history data - error:",GetLastError(),"!!");
      ResetLastError();
      return;
     }
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied2=CopyRates(Symbol(),Period(),0,Bars(Symbol(),Period()),rates); // Copied all datas
   double fechAtual= rates[0].close;
   double fechDiaAnt= rates[1].close;        // rates[1].high,rates[1].open for high
   datetime t1 = rates[0].time;   
   double rsiPeak = iRSI(_Symbol, PERIOD_D1, 2, PRICE_CLOSE);

   CopyBuffer(handle,0,0,3,iRSIBuffer);
   if (sizeof(iRSIBuffer) < 3) {
      return;
   }
   //double rsiPeak = iRSI(NULL, 0, 2, PERIOD_CURRENT);
   verifiquePosicaoAberta();   
   bool Buy_Condition = iRSIBuffer[2] < 30;
   if (Buy_Condition) {
      if (Buy_opened) 
      {
         Alert("We already have a Buy Position!!!"); 
         return;    // Don't open a new Buy Position
      }
   }
   double maxTresPeriodos = findMaxPeriodos(rates);
   FileWrite(handleFile, _Symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS ), rates[0].open, rates[0].high, rates[0].low, rates[0].close, rates[0].real_volume, rates[1].open, rates[1].high, rates[1].low, rates[1].close, rates[1].real_volume, NormalizeDouble(iRSIBuffer[2], 2), NormalizeDouble(iRSIBuffer[1], 2), maxTresPeriodos);
  }
//+------------------------------------------------------------------+

double findMaxPeriodos(MqlRates &rates[]) {
   double max = 0;
   for (int i=0; i<3;i++) {
     if (rates[i].high > max) {
        max = rates[i].high; 
     }
   }
   return max;
}

void verifiquePosicaoAberta() {
//--- we have no errors, so continue
//--- Do we have positions opened already?
    if (PositionSelect(_Symbol) ==true)  // we have an opened position
    {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            Buy_opened = true;  //It is a Buy
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            Sell_opened = true; // It is a Sell
         }
    }
}
/*
void envieOrdem(MqlRates rate) {
   MqlTradeRequest mrequest;

   mrequest.action = TRADE_ACTION_DEAL;                                // immediate order execution
   mrequest.price = NormalizeDouble(rate.ask,_Digits);          // latest ask price
   mrequest.sl = NormalizeDouble(rate.ask - STP*_Point,_Digits); // Stop Loss
   mrequest.tp = NormalizeDouble(rate.ask + TKP*_Point,_Digits); // Take Profit
   mrequest.symbol = _Symbol;                                         // currency pair
   mrequest.volume = Lot;                                            // number of lots to trade
   mrequest.magic = EA_Magic;                                        // Order Magic Number
   mrequest.type = ORDER_TYPE_BUY;                                     // Buy Order
   mrequest.type_filling = ORDER_FILLING_FOK;                          // Order execution type
   mrequest.deviation=100;                                            // Deviation from current price
   //--- send order
   OrderSend(mrequest,mresult);
}*/

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
