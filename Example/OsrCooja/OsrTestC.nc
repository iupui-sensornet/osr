#include <Timer.h>
#include "OsrTest.h"
/*
 * for unicast version
 */
//#include <AM.h>
//#include <message.h>
//#include "TreeRouting.h"
//#include "Ctp.h"
module OsrTestC {
	uses interface Boot;
	uses interface Leds;
	uses interface SplitControl as RadioControl;
	uses interface StdControl as OsrControl;
	
	uses interface Timer<TMilli> as DataTimer;
	uses interface AMPacket;
	
	// ctp controls
	uses interface StdControl as CtpControl;
	uses interface RootControl;
	
	// ctp data collection
	uses interface Send as DataSend;
	uses interface Receive as DataReceive;
	uses interface Intercept as DataIntercept;	// record the routing path
	uses interface CtpPacket;
	uses interface CtpInfo;
	
	// command reply message using ctp
	uses interface Send as ReplySend;			// send command_reply
	uses interface Receive as ReplyReceive;		// sink receive command_reply

	// TOSSIM communication
	uses interface Receive as SimReceive;		// receive TOSSIM packet to start dissemination
	
	// OSR send and receive
	uses interface Send as OsrSend;
	uses interface Receive as OsrReceive;
	uses interface OsrPacket;
	uses interface BloomFilter;					// get bFlt bits of this node id
	uses interface ChildrenTable;

}
implementation {
	
	message_t data_pkt;
	message_t reply_pkt;
	message_t sim_pkt;
	message_t osr_pkt;
	
	osr_test_msg_t* o_msg; 
	
	bool radioBusy = FALSE;	// a radio busy controls all the radio activity
	uint16_t rounds = 0;
	uint8_t i = 0;
	
	uint64_t path_bflt[2];		// the bloom filter that encodes the 
							// path
	uint16_t target_id = 0xffff;
	
	// variables for reply packet
	// shared by sink and node
	uint16_t	reply_cmd_seqno;			// seqno of the sink's cmd
	uint8_t reply_cmd;				// the cmd type recieved from sink
	uint8_t	reply_rnd;				// a random number from sink
	uint16_t reply_new_value;	// the value
	uint16_t reply_nodeid;
	
	
	// data payload
	uint16_t counter = 0;	// data payload
	am_addr_t parent = 0xFFFF;
	uint8_t cmd;			// the cmd type
	uint16_t new_value;	// the new value
	
	uint16_t path[MAX_PATH_LEN];	// the full path for a node to check whether it is false positive
	
	// the parameter
	uint32_t interval = DEF_INTERVAL;
	
	uint16_t value = 0;
	
	// others
	uint16_t sink_timer_count = 0;
	
	event void Boot.booted() {
		/*
	 	 * for unicast version
	 	 */
		o_msg = (osr_test_msg_t*)call OsrSend.getPayload(&osr_pkt, sizeof(osr_test_msg_t));
		
		call RadioControl.start();
		call OsrControl.start();
		dbg("Boot", "Mote Booted!\n");
		
		path_bflt[0] = 0;
		path_bflt[1] = 0;
	
		for(i = 0; i < MAX_PATH_LEN; i++) {
			path[i] = 0;
		}
	}
	
	event void RadioControl.startDone(error_t err) {
		if (err != SUCCESS)
			call RadioControl.start();
		else {
		
			call CtpControl.start();
			
	  		if (TOS_NODE_ID == SINK_ADDR) {
				call RootControl.setRoot();
				dbg("Root", "Root: set root\n");
				call DataTimer.startPeriodic((uint32_t) interval/2);
	  		} else {
		  		dbg("Timer", "Timer: start timer of interval: %d\n", interval);
		  		call DataTimer.startPeriodic((uint32_t) interval);
	  		}
	  		
		}
	}
	
	/************************* Data collection logic **************************/
	
	/*
	 * Send data packet
	 */
	task void sendDataMessage() {
		data_msg_t* d_msg = (data_msg_t*) call DataSend.getPayload(&data_pkt, sizeof(data_msg_t));
	
		d_msg->data = counter++;
		// TODO
		
		if ((call CtpInfo.getParent(&parent)) != SUCCESS) {
			dbg("CtpParent", "CtpParent: get parent fail\n");
		}
		d_msg->parent = parent;
		for(i = 0; i < MAX_PATH_LEN; i++){
			d_msg->path[i] = 0;
		}
		d_msg->value = value;
		
		if (call DataSend.send(&data_pkt, sizeof(data_msg_t)) != SUCCESS) {
	  		dbg("DataSend", "DataSend: send data packet FAIL(len: %hu)\n", sizeof(data_msg_t));
	    } else {
	  		radioBusy = TRUE;
		  	dbg("DataSend", "DataSend: send data packet (counter: %hu)\n", d_msg->data);
	    }
	}
	/*
	 * Data timer fired, collect data 
	 */
	event void DataTimer.fired() {
		if(TOS_NODE_ID == SINK_ADDR) {
			sink_timer_count++;
			if(sink_timer_count % 2 == 0) {
				rounds++;
			}
		}
		else {	
		
			if(!radioBusy) {
				post sendDataMessage();
			}
		}
	}
	
	/*
	 * Intermediate nodes intercept the data packet, and fill the path 
	 */
	event bool DataIntercept.forward(message_t* msg, void* payload, uint8_t len){
		uint8_t hopCounter = call CtpPacket.getThl(msg);
		uint16_t child = call AMPacket.source(msg);
		data_msg_t* i_msg = (data_msg_t*) payload;
		
		// for the path, record the link layer sender of the packet 
		if(hopCounter > 1 && hopCounter <= MAX_PATH_LEN) {
			// the first hop sender is the source of CTP packet, no need to record it
			i_msg->path[hopCounter-2] = child;	
		}else if (hopCounter == 1){
			i_msg->path[hopCounter-1] = 0;	
		}
			
		return TRUE;
	}
	
	/*
	 * Sink receive data packet, do nothing, or record the path
	 */
	event message_t* DataReceive.receive(message_t* msg, void* payload, uint8_t len) {
		if (len != sizeof(data_msg_t)) {
			dbg("Root", "Root: the data msg payload length does not match\n");
		} else {
			uint16_t source;
			uint8_t hopCounter;
			uint8_t seqno;
			uint16_t child = call AMPacket.source(msg);
			data_msg_t* rcm = (data_msg_t*)payload;

			source = call CtpPacket.getOrigin(msg);
 	 		seqno = call CtpPacket.getSequenceNumber(msg);
 	 		hopCounter = call CtpPacket.getThl(msg);

			if(hopCounter > 1 && hopCounter <= MAX_PATH_LEN) {
				rcm->path[hopCounter-2] = child;	
				rcm->path[hopCounter-1] = TOS_NODE_ID;	
			}else if (hopCounter == 1){
				rcm->path[hopCounter-1] = TOS_NODE_ID;	
			}
			
			dbg("DATA", "data: %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", 
					rounds, source, seqno, hopCounter, rcm->parent, rcm->path[1], 
					rcm->path[2], rcm->path[3], rcm->path[4], rcm->path[5], rcm->path[6],
					rcm->path[7], rcm->path[8], rcm->path[9],rcm->path[10],rcm->path[11],
					rcm->path[12], rcm->path[13], rcm->path[14], rcm->path[15], rcm->path[16],
					rcm->path[17], rcm->path[18], rcm->path[19], rcm->path[20], rcm->path[21], 
					rcm->path[22], rcm->path[23], rcm->path[24], rcm->path[25], rcm->path[26],
					rcm->path[27], rcm->path[28], rcm->path[29], rcm -> data, rcm->value);
			
			// update children table
			// ROOT will call this
			call ChildrenTable.update(child);
	
		}    
		return msg;
	}
	
	
	event void DataSend.sendDone(message_t* msg, error_t err) {
		if (err != SUCCESS) {
	  		dbg("Mote", "Mote: sendDone FAIL\n");
	    }
		else {
			dbg("Mote", "Mote: sendDone SUCCESS\n");
		}
		radioBusy = FALSE;
	}
	
	
	/******************************* Sink logic ********************************/
	/*
	 * Sink receive TOSSIM command packet, and broadcast this packet to the network
	 */
	event message_t* SimReceive.receive(message_t* msg, void* payload, uint8_t len) {
		if(len != sizeof(sim_msg_t)) {
			dbg("SimReceive", "SimReceive: wrong sim packet\n");
			return msg;
		} else {
			uint64_t tmp_bflt[2];
			
			sim_msg_t* s_msg = (sim_msg_t*)payload;
			
			tmp_bflt[0] = 0;
			tmp_bflt[1] = 0;
			
			path_bflt[0] = 0;
			path_bflt[1] = 0;
			
			
			for(i = 0; i < s_msg->path_len; i++) {
				tmp_bflt[0] = 0;
				tmp_bflt[1] = 0;
				call BloomFilter.getBflt(s_msg->path[i], &tmp_bflt[0], &tmp_bflt[1], 128);
				
				dbg("SimReceive", "SimReceive: compute bflt for hop i: %hu \n", i);
				path_bflt[0] = path_bflt[0] | tmp_bflt[0];
				path_bflt[1] = path_bflt[1] | tmp_bflt[1];
				
			}	
			
			cmd = s_msg->cmd;
			new_value = s_msg->new_value;
			target_id = s_msg->target_id;
			
			o_msg->cmd = s_msg->cmd;
			o_msg->new_value = s_msg->new_value;
			target_id = s_msg->target_id;
			
			// set path bflt and target id using OsrPacket, and send the downstream packet			
			call OsrPacket.setPathBflt(&osr_pkt, path_bflt[0], path_bflt[1]);
			call OsrPacket.setDestination(&osr_pkt, target_id);
			
			call OsrSend.send(&osr_pkt, sizeof(osr_test_msg_t));
			
			dbg("SimReceive", "SimReceive: Downstream Message sent \n");
			
			for(i = 0; i < MAX_PATH_LEN; i++){
				path[i] = s_msg->path[i];
			}
			return msg;
		}
	}
	
	event message_t* ReplyReceive.receive(message_t* msg, void* payload, uint8_t len) {
		if (len != sizeof(reply_msg_t)) {
			dbg("Root", "Root: the reply msg payload length does not match\n");
			return msg;
		}else {
			reply_msg_t* r_msg = (reply_msg_t*)payload;
		
			reply_cmd_seqno = r_msg->reply_cmd_seqno;
			reply_cmd 		= r_msg->reply_cmd;
			reply_rnd		= r_msg->reply_rnd;
			reply_new_value	= r_msg->reply_new_value;
		
			reply_nodeid 	= call CtpPacket.getOrigin(msg);
		
			dbg("OSR", "seqno: %hu, Cmd Reply Receive: at time: %s, reply_id: %d, cmd: %d, rnd: %d, new_value: %d\n",
						reply_cmd_seqno, sim_time_string(), reply_nodeid, reply_cmd, reply_rnd, reply_new_value);
		
			return msg;
		}
	}
	
	event void OsrSend.sendDone(message_t* msg, error_t err) {
		radioBusy = FALSE;
	} 
	
	/******************************* Node logic ********************************/
	
	/*
	 * Send reply packet
	 */
	task void sendReplyMessage() {
		reply_msg_t* r_msg = (reply_msg_t*)call ReplySend.getPayload(&reply_pkt, sizeof(reply_msg_t));
		
		if ((call CtpInfo.getParent(&parent)) != SUCCESS) {
			dbg("CtpParent", "CtpParent: get parent fail\n");
		}
		r_msg->parent = parent;
		r_msg->reply_cmd_seqno = reply_cmd_seqno;
		r_msg->reply_cmd = reply_cmd;
		r_msg->reply_rnd = reply_rnd;
		r_msg->reply_new_value = reply_new_value;
		
		if (call ReplySend.send(&reply_pkt, sizeof(reply_msg_t)) != SUCCESS) {
	  		dbg("ReplySend", "seqno: %hu, ReplySend: send reply packet FAIL(len: %hu)\n", reply_cmd_seqno, sizeof(reply_msg_t));
	    } else {
	  		radioBusy = TRUE;
		  	dbg("ReplySend", "seqno: %hu, ReplySend: send reply packet: reply seqno: %hu\n", reply_cmd_seqno, reply_cmd_seqno);
	    }
	}
	
	/*
	 * Node receives a command packet, check whether the node is in the path
	 */
	event message_t* OsrReceive.receive(message_t* msg, void* payload, uint8_t len){

		if (len != sizeof(osr_test_msg_t)) {
			dbg("OSR", "OSR_Receive: the cmd msg payload length does not match\n");
			return msg;
		} else{
			osr_test_msg_t* rcv_o_msg = (osr_test_msg_t*)payload;
			
			// TODO: send reply
			call CtpInfo.getParent(&parent);
			
			reply_cmd_seqno = call OsrPacket.getSeqno(msg);
			reply_rnd		= call OsrPacket.getRnd(msg);;
			reply_cmd		= rcv_o_msg->cmd;
			
			reply_new_value	= rcv_o_msg->new_value;
			
			dbg("OSR", "seqno: %d, OSR_Receive: received! OSR downstream packet\n", call OsrPacket.getSeqno(msg));
			post sendReplyMessage();
			
			return msg;
		}
	}
	
	event void ReplySend.sendDone(message_t* msg, error_t err) {
		radioBusy = FALSE;
	}

	event void RadioControl.stopDone(error_t err) {}
	
}			
