/*
 * Implementation of OSR 
 *
 */
#include "osr.h"

configuration OsrP {
	provides {
		interface StdControl;
		interface Send[uint8_t client];
		interface Receive[osr_id_t id];
		interface Receive as Snoop[osr_id_t id];// not useful now
//		interface Intercept[osr_id_t id];
		
		interface Packet;
		interface OsrPacket;
		interface ChildrenTable;

	}
	uses {
		interface OsrId[uint8_t client];
//		interface Intercept[collection_id_t id];	// RBD style
	}
}

implementation {
	enum {
		OSR_CLIENT_COUNT = uniqueCount(UQ_OSR_CLIENT),
		OSR_POOL_SIZE = 4,		// queue size is 4
		OSR_QUEUE_SIZE = OSR_CLIENT_COUNT + OSR_POOL_SIZE,
	};
	
	components ActiveMessageC;
	components new OsrForwarderP() as forwarder;
	components MainC, LedsC;
	
	Send = forwarder;
	StdControl = forwarder;
	Receive = forwarder.Receive;
	Snoop = forwarder.Snoop;
//	Intercept = forwarder;		// RBD style, hold on
	Packet = forwarder;
	OsrPacket = forwarder;
	ChildrenTable = forwarder;
	
	// uses
	OsrId = forwarder;
	
	MainC.SoftwareInit -> forwarder;
	forwarder.Leds -> LedsC;
	forwarder.RadioControl -> ActiveMessageC;
	
	components new PoolC(message_t, OSR_POOL_SIZE) as MessagePoolP;
	components new PoolC(osr_fe_queue_entry_t, OSR_POOL_SIZE) as QEntryPoolP;
	forwarder.QEntryPool -> QEntryPoolP;
	forwarder.MessagePool -> MessagePoolP;
	
	components new QueueC(osr_fe_queue_entry_t*, OSR_QUEUE_SIZE) as SendQueueP;
	forwarder.SendQueue -> SendQueueP;
	
	components new TimerMilliC() as RetxTimerC;
	forwarder.RetxTimer -> RetxTimerC;
	
	components new TimerMilliC() as TableTimerC;
	forwarder.TableTimer -> TableTimerC;
	
	components RandomC;
	forwarder.Random -> RandomC;
	forwarder.SeedInit -> RandomC;
	
	components new AMSenderC(AM_OSR_DATA);
	components new AMReceiverC(AM_OSR_DATA);
	components new AMSnooperC(AM_OSR_DATA);
	
	forwarder.SubSend -> AMSenderC;
	forwarder.PacketAcknowledgements -> AMSenderC.Acks;
	forwarder.SubPacket -> AMSenderC;
	forwarder.SubReceive -> AMReceiverC;
	forwarder.SubSnoop -> AMSnooperC;
	forwarder.AMPacket -> AMSenderC;
	
	components CollectionC;
	forwarder.CtpInfo 	-> CollectionC;
	forwarder.Intercept	-> CollectionC.Intercept;
	forwarder.CtpPacket -> CollectionC;
	forwarder.RootControl -> CollectionC;
	
	components OsrInstrumentationP;
	forwarder.OsrInstrumentation -> OsrInstrumentationP;
	
	components BloomFilterC;
	forwarder.BloomFilter -> BloomFilterC;
	
	#if defined(ENABLE_SNOOP_CHILDREN) // for snoop children 
	forwarder.CtpSnoop -> CollectionC.Snoop;	// snoop all CTP data packets 
	#endif

}
