#include "OsrTest.h"


configuration OsrTestAppC {
}
implementation {
	components OsrTestC as App, MainC, LedsC;
	App.Boot		-> MainC;
	App.Leds		-> LedsC;
	
	components new TimerMilliC() as DataTimerC;
	App.DataTimer 	-> DataTimerC;
	
	components ActiveMessageC as RadioAM;
	App.RadioControl 	-> RadioAM;
	
	components CollectionC as Collector;
	App.CtpControl		-> Collector;
	App.RootControl		-> Collector;
	
	// ctp send data
	components new CollectionSenderC(CTP_DATA_MSG) as CtpDataSenderC;
	App.DataSend		-> CtpDataSenderC;
	App.DataReceive		-> Collector.Receive[CTP_DATA_MSG];
	App.DataIntercept	-> Collector.Intercept[CTP_DATA_MSG];
	App.CtpInfo 		-> Collector;
	App.CtpPacket 		-> Collector;
	
	// ctp send reply 
	components new CollectionSenderC(CTP_REPLY_MSG) as CtpReplySenderC;
	App.ReplySend		-> CtpReplySenderC;
	App.ReplyReceive	-> Collector.Receive[CTP_REPLY_MSG];
	
	
	components new AMReceiverC(AM_SIM_MSG) as SimReceiverC;
	App.SimReceive	-> SimReceiverC;	
	
	// get ctp routing information
//	App.CtpRoutingInfo -> Collector;
	App.AMPacket -> RadioAM;
	
	// OSR
	components new OsrSenderC(0xcc);
	App.OsrSend -> OsrSenderC;
	
	App.OsrPacket -> OsrSenderC;
	
	components OsrC;
	App.OsrReceive -> OsrC.Receive[0xcc];
	App.ChildrenTable -> OsrC;
	App.OsrControl -> OsrC;
	
	// bloom filter
	components BloomFilterC;
	App.BloomFilter -> BloomFilterC;
	
	
}
