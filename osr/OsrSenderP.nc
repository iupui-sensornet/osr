

#include "osr.h"
generic configuration OsrSenderP(osr_id_t osrid, uint8_t clientid) {
	provides {
		interface Send;
		interface Packet;
		interface OsrPacket;
	}
}

implementation {
	components OsrC;
	components new OsrIdP(osrid);
	
	Send = OsrC.Send[clientid];
	Packet = OsrC.Packet;
	OsrPacket = OsrC.OsrPacket;
	
	OsrC.OsrId[clientid] -> OsrIdP;
	
}


