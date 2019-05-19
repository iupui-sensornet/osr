#include "osr.h"

generic module OsrIdP(osr_id_t osrid) {
	provides interface OsrId;
}

implementation {
	command osr_id_t OsrId.fetch() {
		return osrid;
	}
}
