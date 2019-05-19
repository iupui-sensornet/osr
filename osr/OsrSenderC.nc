

#include "osr.h"

generic configuration OsrSenderC(osr_id_t osrid) {
	provides {
		interface Send;
		interface Packet;
		interface OsrPacket;
	}
}

implementation {
	components new OsrSenderP(osrid, unique(UQ_OSR_CLIENT));
	Send = OsrSenderP;
	Packet = OsrSenderP;
	OsrPacket = OsrSenderP;

}
