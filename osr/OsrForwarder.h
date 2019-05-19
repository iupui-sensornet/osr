#ifndef OSR_FORWARDER_H
#define OSR_FORWARDER_H

#include <AM.h>
#include <message.h>


/* 
 * These timings are in milliseconds, and are used by
 * Forwarder. Each pair of values represents a range of
 * [OFFSET - (OFFSET + WINDOW)]. The Forwarder uses these
 * values to determine when to send the next packet after an
 * event. FAIL refers to a send fail (an error from the radio below),
 * NOACK refers to the previous packet not being acknowledged,
 * OK refers to an acknowledged packet, and LOOPY refers to when
 * a loop is detected.
 *
 * These timings are defined in terms of packet times. Currently,
 * two values are defined: for CC2420-based platforms (4ms) and
 * all other platfoms (32ms). 
 */

enum {
#if PLATFORM_MICAZ || PLATFORM_TELOSA || PLATFORM_TELOSB || PLATFORM_TMOTE || PLATFORM_INTELMOTE2 || PLATFORM_SHIMMER || PLATFORM_IRIS
	OSR_FORWARD_PACKET_TIME = 7,
#else
	OSR_FORWARD_PACKET_TIME = 32,
#endif
};

enum {
	OSR_SENDDONE_OK_OFFSET        = OSR_FORWARD_PACKET_TIME,		// the time before transmitting next packet 
	OSR_SENDDONE_OK_WINDOW        = OSR_FORWARD_PACKET_TIME,
	OSR_SENDDONE_NOACK_OFFSET     = OSR_FORWARD_PACKET_TIME,		// the time before retransmission
	OSR_SENDDONE_NOACK_WINDOW     = OSR_FORWARD_PACKET_TIME,
	OSR_SENDDONE_FAIL_OFFSET      = OSR_FORWARD_PACKET_TIME  << 2,	// when transmission failed, wait a little bit longer
	OSR_SENDDONE_FAIL_WINDOW      = OSR_SENDDONE_FAIL_OFFSET,
	
	OSR_BCAST_WINDOW	  = OSR_SENDDONE_FAIL_WINDOW,	// Bcast due to unicast failure.
	OSR_BCAST_OFFSET	  = OSR_SENDDONE_FAIL_OFFSET,
//	OSR_SENDDONE_NEXT_WINDOW	  = OSR_SENDDONE_FAIL_WINDOW,	//  send to the next direct children 
//	OSR_SENDDONE_NEXT_OFFSET	  = OSR_SENDDONE_FAIL_OFFSET,

	OSR_MCAST_OFFSET	  = OSR_SENDDONE_FAIL_OFFSET,	// multicast due to multiple matched children
	OSR_MCAST_WINDOW	  = OSR_SENDDONE_FAIL_WINDOW,
	
};

// the max length of the bloom filter array, in bytes 
#ifndef MAX_BFLT_LEN
#define MAX_BFLT_LEN 16
#endif

// the default time interval to update the children table 
// DEFAULT: 30 minutes in real world testbed
#ifndef TABLE_UPDATE_INTERVAL
#define TABLE_UPDATE_INTERVAL 1024*60*30
#endif

// direct children table size 
#ifndef OSR_CHILDREN_SIZE
#define OSR_CHILDREN_SIZE 10
#endif

// max children ttl 
// Absolute time = TABLE_UPDATE_INTERVAL * MAX_CHILD_TTL
#ifndef MAX_CHILD_TTL
#define MAX_CHILD_TTL 4
#endif

#ifndef OSR_HISTORY_SIZE
#define OSR_HISTORY_SIZE 4
#endif

// for snoop children 
#ifndef SNOOP_SIZE
#define SNOOP_SIZE 3
#endif

// others
enum{
	
	OSR_UCAST_RETRIES = 10,		// in default is 10
	OSR_MCAST_RETRIES = OSR_UCAST_RETRIES >> 1,		// if high power 
	OSR_BCAST_RETRIES	= OSR_UCAST_RETRIES >> 1,	// Bcast retries, due to opportunistic routing 
//	OSR_MCAST_RETRIES = OSR_UCAST_RETRIES,			// if ucast retx is low
//	OSR_BCAST_RETRIES	= OSR_UCAST_RETRIES,


//	OSR_BCAST_RETRIES	= 3,							// no need to have ack, transmit less times 
	
	// OSR transmission types, mainly used for debugging
	OSR_UCAST = 0x00,
	OSR_MCAST = 0x01,
	OSR_BCAST = 0x02,

	MCAST_THRD = 1,	// if the matched number of children is larger than this,
					// broadcast the packet

};



/*
 * An element in the Forwarder send queue.
 * The client field keeps track of which send client 
 * submitted the packet or if the packet is being forwarded
 * from another node (client == 255). Retries keeps track
 * of how many times the packet has been transmitted.
 */

typedef struct {
	message_t * ONE_NOK msg;
	uint8_t client;
	int8_t retries;
	uint16_t next_hops[OSR_CHILDREN_SIZE];	// each message has its own next_hops
  											// the possible number equals to the children number
	int8_t cur_next_hop_idx;
	bool unicast_ever_failed;		// set to TRUE as long as there is a unicast failure
	int8_t pending_acks;	// matches the nodes in the next_hops array, used in Snoop
	nx_uint8_t rcv_option;	// the option of the packet upon receiving time

} osr_fe_queue_entry_t;

// direct children table entry
typedef struct {
	uint16_t id;
	int8_t ttl;
} children_table_entry_t;




#endif
