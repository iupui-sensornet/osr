#ifndef OSR_TEST_H
#define OSR_TEST_H

// message types
enum {
	AM_SIM_MSG = 0x81,
	
	CTP_DATA_MSG = 0xDD,
	CTP_REPLY_MSG = 0xDE,
	
};

// downstream command types
enum {
	SET_INTERVAL = 1,
	SET_POWER = 2,
};


// others
enum{
	MAX_PATH_LEN = 30,
	
	SINK_ADDR = 1,
	DEF_INTERVAL = 1024*60*15,		//default timer interval
	
};


// general data message of CTP
typedef nx_struct DataMsg {
  	nx_uint16_t parent;
  	nx_uint16_t data;	// data
  	nx_uint16_t path[MAX_PATH_LEN];	// MAX_PATH_LEN = 30
  	nx_uint16_t value;
} data_msg_t;

// command/control message from sink to node
typedef nx_struct Osr_Test_Msg {
	nx_uint8_t 	cmd;		// the cmd type
	nx_uint16_t new_value;	// the new value
	
} osr_test_msg_t;
	
// nodes' reply message of sink's command
typedef nx_struct ReplyMsg {
	nx_uint16_t parent;
  	
	nx_uint16_t	reply_cmd_seqno;			// seqno of the sink's cmd
	nx_uint8_t 	reply_cmd;				// the cmd type recieved from sink
	nx_uint8_t	reply_rnd;				// a random number from sink
	nx_uint16_t reply_new_value;	// the value
} reply_msg_t;

// control message from PC to sink to initial a dissemination of a command 
typedef nx_struct SimMsg {
	nx_uint8_t path_len;
	nx_uint16_t path[MAX_PATH_LEN];	// MAX_PATH_LEN = 30
  	nx_uint16_t target_id;
	nx_uint8_t 	cmd;		// the cmd type
	nx_uint16_t new_value;	// the new value
	nx_uint16_t net_size;	// the size of the network, for testing purpose
} sim_msg_t;		


#endif


