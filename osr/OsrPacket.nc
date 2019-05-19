/*
 * Interface to manipulate an OSR downstream packet
 *
 *
 */
#include "osr.h"
interface OsrPacket {
	/*
	 * Set the Bloom filter of the downstream packet, 
	 *
	 */
	command void setPathBflt(message_t* msg, nx_uint8_t* bflt);
	command void getPathBflt(message_t* msg, nx_uint8_t* bflt);
	
	command void setDestination(message_t* msg, uint16_t targetId);
	command uint16_t getDestination(message_t* msg);
	
	command void setSeqno(message_t* msg, uint8_t seq);
	command uint16_t getSeqno(message_t* msg);
	
	command uint8_t getRnd(message_t* msg);
	
	command void setType(message_t* msg, osr_id_t type);
	command uint8_t getType(message_t* msg);
	
	command void setPathLen(message_t* msg, uint8_t len);
	command uint8_t getPathLen(message_t* msg);
	
	// for debug only, set the actual downstream path 
//			

	
	#if defined(INDRIYA_ENABLED)
	command void setDownPath(message_t* msg, uint8_t* path);		// for Indriya to save RAM
	#else
	command void setDownPath(message_t* msg, uint16_t* path);
	#endif
}
