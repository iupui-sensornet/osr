#ifndef OSR_H
#define OSR_H
#include <OsrForwarder.h>

typedef uint8_t osr_id_t;
typedef nx_uint8_t nx_osr_id_t;

////// TODO: add another component for the unique id
#define UQ_OSR_CLIENT "OsrSenderC.OsrId"

// message types
enum {
	AM_OSR_DATA = 0x80,				// for both sink and mote
	
};


// sink state
enum {
	WAITING_REPLY = 1,			// state machine
	READY = 2,
};

// command/control message from sink to node
// header size = 10 bytes
typedef nx_struct Osr_Header {
	nx_uint16_t	seqno;	// seqno of the cmd
	nx_uint8_t	rnd;		// a random number from sink
	nx_uint8_t option;		// use 1 bit to indicate ucast/bcast, other bits for other use
//	nx_uint8_t path_bflt[MAX_BFLT_LEN];		// the bloom filter that encodes the 
									// path, 128 bits
									// TODO: move to the tail for dynamic bflt len
  	nx_uint8_t path_len;
  	nx_uint16_t target_id;
  	nx_int8_t ttl;
	nx_osr_id_t type;		// osr packet id
							// 8 bytes until now
							
	nx_uint16_t next_hop;	// REMOVE FOR FINAL RELEASE. 			2 btyes
							// The next hop in the downstream path
							// Usually it is the direct children id.

	nx_uint16_t down_path[MAX_PATH_LEN];	// for debug only, for 20 hops, it is 40 bytes 
	
	nx_uint8_t (COUNT(0) data)[0]; // Deputy place-holder, field will probably be removed when we Deputize OSR
} osr_header_t;


// TODO: use the tail to store the path Bloom filter, so that to make the dynamic
// Bflt
// 
typedef nx_struct Osr_tail {
	nx_uint8_t path_bflt[MAX_BFLT_LEN];		// MAX_BFLT_LEN = 16, 128 bits
} osr_tail_t;
	


#endif


