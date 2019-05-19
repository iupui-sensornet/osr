#include "osr.h"

configuration OsrC {
	provides {
		interface StdControl;
		interface Send[uint8_t client];
		interface Receive[osr_id_t id];
		interface Receive as Snoop[osr_id_t id];
//		interface Intercept[osr_id_t id];
		
		interface Packet;
		interface OsrPacket;
		interface ChildrenTable;

	}
	uses {
		interface OsrId[uint8_t client];
	}
}

implementation {
	components OsrP;
	
	StdControl = OsrP;
	Send = OsrP;
	Receive = OsrP.Receive;
	Snoop = OsrP.Snoop;
//	Intercept = OsrP;
	
	Packet = OsrP;
	OsrPacket = OsrP;
	ChildrenTable = OsrP;
	
	OsrId = OsrP;
	
}
