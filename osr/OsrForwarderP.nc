/*
 * Implementation of OSR 
 *
 */
#include <OsrForwarder.h>
#include <osr.h>
 
generic module OsrForwarderP() {
	provides {
		interface Init;
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
		interface Leds;
	
		// send and receive commands
		// OSR forwarding functionalities
		interface AMSend as SubSend;			// broadcast command packet
		interface PacketAcknowledgements;
		interface Packet as SubPacket;
		interface Timer<TMilli> as RetxTimer;
		interface Timer<TMilli> as TableTimer;
		
		// These four data structures are used to manage packets to forward.
		// SendQueue and QEntryPool are the forwarding queue.
		// MessagePool is the buffer pool for messages to forward.
		interface Queue<osr_fe_queue_entry_t*> as SendQueue;
		interface Pool<osr_fe_queue_entry_t> as QEntryPool;
		interface Pool<message_t> as MessagePool;
		
		interface Receive as SubReceive;		// receive command packet
		interface Receive as SubSnoop;
		interface CtpInfo;
		interface CtpPacket;
		interface OsrId[uint8_t client];
		interface RootControl;
		
		interface BloomFilter;		// get bFlt bits of this node id
									// or can be implemented using a function call
		
		interface AMPacket;
		// intercept each got through CTP packets in order to update the children table
		interface Intercept[collection_id_t id];	
		interface Random;			// random number for unique command
		interface ParameterInit<uint16_t> as SeedInit;
		
		interface SplitControl as RadioControl;	// stop forwarding if underlying radio is off
		
		interface OsrInstrumentation;
		
	}
}

implementation {

	/* Helper functions
	 */
	static void startRetxTimer(uint16_t mask, uint16_t offset);
	bool hasSeen(uint8_t cur_seq, uint8_t cur_rnd);
	void insert(uint8_t cur_seq, uint8_t cur_rnd);
	bool bfltMatched(nx_uint8_t* bflt1, nx_uint8_t* bflt2);
	
	void clearState(uint8_t state);
	bool hasState(uint8_t state);
	void setState(uint8_t state);
	
	enum {
		ROUTING_ON       = 0x1, // Forwarding running?
		RADIO_ON         = 0x2, // Radio is on?
		ACK_PENDING      = 0x4, // Have an ACK pending?
		SENDING          = 0x8 // Am sending a packet?
	};
	
	// Start with all states false
	uint8_t forwardingState = 0; 
	
	// osr sequence number
	uint16_t seqno;

	enum {
		CLIENT_COUNT = uniqueCount(UQ_OSR_CLIENT)
	};
	
	/* Each sending client has its own reserved queue entry.
     If the client has a packet pending, its queue entry is in the 
     queue, and its clientPtr is NULL. If the client is idle,
     its queue entry is pointed to by clientPtrs. */

	osr_fe_queue_entry_t clientEntries[CLIENT_COUNT];
	osr_fe_queue_entry_t* ONE_NOK clientPtrs[CLIENT_COUNT];
	
	struct {
		uint16_t seqno;
		uint8_t rnd;
	} receivedOSRs[OSR_HISTORY_SIZE];
	
	children_table_entry_t children[OSR_CHILDREN_SIZE];
	
	/////////////////////// the rest variables hold here ///////////////////////
	
	uint8_t next_history_index = 0;
	uint8_t cur_next_hop_idx = 0;
	
	// debug variables
	uint16_t pre_parent = 0xffff;
	uint16_t parent = 0xffff;
	
	// children table
	uint8_t child_idx = 0;
	uint8_t children_count = 0;
	
	// 
	nx_uint8_t my_bflt[MAX_BFLT_LEN];		// local node's bflt
	nx_uint8_t chd_bflt[MAX_BFLT_LEN];		// children's bflt
	
	bool snoop_comlete = FALSE;		// packet complete through Snoop	
	////////////////////////////////////////////////////////////////////////////
	
	/************************** Initialization ********************************/
	command error_t Init.init() {
		int i = 0;
		for (i = 0; i < CLIENT_COUNT; i++) {
			clientPtrs[i] = clientEntries + i;
		}
		
		for(i = 0; i < OSR_HISTORY_SIZE; i++) {
			receivedOSRs[i].seqno = 0;
			receivedOSRs[i].rnd = 0;
		}
		
		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			children[i].id = 0;
			children[i].ttl = 0;
		}
		
		call SeedInit.init(TOS_NODE_ID);
		
		seqno = 0;
		
		return SUCCESS;
	}
	
	command error_t StdControl.start() {
		setState(ROUTING_ON);
		// start to manage the children table 
		call TableTimer.startPeriodic((uint32_t)TABLE_UPDATE_INTERVAL);
		return SUCCESS;
	}

	command error_t StdControl.stop() {
		clearState(ROUTING_ON);
		
		// stop the table timer 
		if(call TableTimer.isRunning()) {
			call TableTimer.stop();
		}
		return SUCCESS;
	}
	
	event void TableTimer.fired() {
		call ChildrenTable.decreaseTtl();
	}
	
	/////////////////////////////////// tasks and functions /////////////////////
	/* sendTask is where the first phase of all send logic
	 * exists (the second phase is in SubSend.sendDone()). */
	task void sendTask();
	
	/* ForwardingEngine keeps track of whether the underlying
	   radio is powered on. If not, it enqueues packets;
	   when it turns on, it then starts sending packets. */ 
	event void RadioControl.startDone(error_t err) {
		if (err == SUCCESS) {
			setState(RADIO_ON);
			if (!call SendQueue.empty()) {
				post sendTask();
			}
		}
	}

	static void startRetxTimer(uint16_t window, uint16_t offset) {
		uint16_t r = call Random.rand16();
		r %= window;
		r += offset;
		call RetxTimer.startOneShot(r);
		dbg("OSR_RETXTIMER", "OSR_RETXTIMER: Rexmit timer will fire in %hu ms\n", r);
	}
	
	event void RadioControl.stopDone(error_t err) {
		if (err == SUCCESS) {
			clearState(RADIO_ON);
		}
	}
	
	osr_header_t* getHeader(message_t* msg) {
		return (osr_header_t*)call SubPacket.getPayload(msg, sizeof(osr_header_t));
  	}
  	
  	// len: the payload length. It is required to get the correct tail.
  	// cannot call Packet.payloadLength(msg). It is possible that the payload length
  	// is not set yet.
	osr_tail_t* getTail(message_t* msg, uint8_t len) {
//		return (osr_tail_t*)call SubPacket.getPayload(msg, call SubPacket.payloadLength(msg));

		return (osr_tail_t*)(len + (uint8_t *)call Packet.getPayload(msg, len + sizeof(osr_tail_t)));
		
  	}
  	
  	/**
	 * Check whether this command is a duplicate commands
	 * 
	 * The next_idx stores the newly received command, overwrites the old history
	 * as the index loops on the history. 
	 */
	bool hasSeen(uint8_t cur_seq, uint8_t cur_rnd) {
		int i;
		atomic {
		
			for(i = 0; i < OSR_HISTORY_SIZE; i++) {
				if(receivedOSRs[i].seqno == cur_seq) {
					if(receivedOSRs[i].rnd == cur_rnd) {
						return TRUE;
					}
				}
			}
		}

		return FALSE;
	}
	
	/**
	 * Insert the current downstream packet to history
	 *
	 * The next_history_index stores the newly received packet, overwrites the old history
	 * as the index loops on the history. 
	 */
	void insert(uint8_t cur_seq, uint8_t cur_rnd) {
		atomic {
			receivedOSRs[next_history_index].seqno = cur_seq;
			receivedOSRs[next_history_index].rnd = cur_rnd;
			next_history_index++;
			next_history_index %= OSR_HISTORY_SIZE;
		}
	}
	
	/*
	 * Check whether the bflt1 is contained in bflt2
	 */
	bool bfltMatched(nx_uint8_t* bflt1, nx_uint8_t* bflt2){
		int j;

		for(j = 0; j < MAX_BFLT_LEN; j++) {
//			dbg("TestMatch", "TestMatch: j: %d, Bflt1: %d, Bflt2: %d\n", j, bflt1[j], bflt2[j]);
			if(bflt1[j] != (bflt1[j] & bflt2[j])) {
				// if any byte is not a match, return FALSE
				dbg("TestMatch", "TestMatch: NOT a match\n");
				return FALSE;
			}
		}
		// all byte matched
		dbg("TestMatch", "TestMatch: MATCHED\n");
		return TRUE;
	}
	
	/* For Debug only
	 * check whether a node is in the downstream path 
	 **/
	bool is_fp_node(nx_uint16_t* down_path, nx_uint16_t id) {
		int i;
		for(i = 0; i < MAX_PATH_LEN; i++) {
			if(down_path[i] == id) {
				// if the id is in the path, it is not a false positive
				return FALSE;
			}
		}
		dbg("TestFP", "TestFP: FOUND False Positive id: %d\n", id);
		return TRUE;
	}
	
	
	/************************** Send command **********************************/
	// Call from the client. Send a downstream message
	command error_t Send.send[uint8_t client](message_t* msg, uint8_t len){
		// Find the next hop, send the packet
		int i;
		osr_header_t* hdr = getHeader(msg);
		osr_tail_t* tail = getTail(msg, len);
		osr_fe_queue_entry_t *qe;
		
		if (!hasState(ROUTING_ON)) {
			return EOFF;
		}
		if (len > call Send.maxPayloadLength[client]()) {
			return ESIZE;
		}
		
		#if defined(PRINTF_OSR_ENABLED)  
			printf(" OSR SINK: receive request from the app, not busy\n" );
			printfflush();
		#endif
			
		dbg("OSR_Send", "seqno: %d, OSR_Send: Received send request from App\n", seqno);
		hdr->seqno = seqno;
		hdr->rnd = call Random.rand16();
		hdr->ttl = 2 * (call OsrPacket.getPathLen(msg));

		seqno++;
//		call SubPacket.setPayloadLength(msg, len + sizeof(osr_header_t));
		call Packet.setPayloadLength(msg, len);
		hdr->type = call OsrId.fetch[client]();
		
		
		insert(hdr->seqno, hdr->rnd);		// send use keep the send cache using the receivedOSRs[]
		
		if (clientPtrs[client] == NULL) {
			dbg("OSR_Send", "seqno: %d, OSR_Send: %s: send failed as client is busy.\n", hdr->seqno, __FUNCTION__);
			return EBUSY;
		}
		
		qe = clientPtrs[client];
		qe->msg = msg;
		qe->client = client;


		////// find next hops
		qe->cur_next_hop_idx = 0;
		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			qe->next_hops[i] = 0;
		}
				
		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			if(children[i].id != 0) {
				int j;
				for(j = 0; j < MAX_BFLT_LEN; j++) {
					chd_bflt[j] = 0;
				}
				
				call BloomFilter.getBflt(children[i].id, chd_bflt, hdr->path_len);
				
				dbg("OSR_Send", "seqno: %d, OSR_Send: compute bflt for child (%hu, ttl: %hu, i: %hu) \n", 
								hdr->seqno, children[i].id, children[i].ttl, i);
				
				if(bfltMatched(chd_bflt, tail->path_bflt)) {
					qe->next_hops[qe->cur_next_hop_idx] = children[i].id;
					qe->cur_next_hop_idx++;		// this is actually the matched count
				}
			}
		}
			
		dbg("OSR_Send", "seqno: %hu, Children count: total children: %hu, included in the path: %hu children\n", 
							hdr->seqno, children_count, qe->cur_next_hop_idx);
		
		// Debug FP
		// for all the matched children, find the false positives
		for(i = 0; i < qe->cur_next_hop_idx; i++) {
			if(is_fp_node(hdr->down_path, qe->next_hops[i])) {
				if(qe->cur_next_hop_idx > MCAST_THRD) {
					dbg("TestFP", "seqno: %d, TestFP: False positive caused multicast.\n", hdr->seqno);
					call OsrInstrumentation.hlth_mcast_count_fp();	// mcast_count caused by false positive
				} else {
					dbg("TestFP", "seqno: %d, TestFP: False positive caused unicast.\n", hdr->seqno);
					call OsrInstrumentation.hlth_ucast_count_fp();	// only one child, but false positive 
				}
				break;
			}
		}
		
		if(qe->cur_next_hop_idx > MCAST_THRD){
			dbg("OSR_Send", "seqno: %hu, Matched %hu children (> MCAST_THRD), multicast the message. \n", 
							hdr->seqno, qe->cur_next_hop_idx);
							
			qe->retries = OSR_MCAST_RETRIES;
			qe->pending_acks = qe->cur_next_hop_idx;
			hdr->next_hop = 22222;
			hdr->option = OSR_MCAST;
			
			call OsrInstrumentation.hlth_mcast_count();
			
		} else if (qe->cur_next_hop_idx > 0) {
			dbg("OSR_Send", "seqno: %hu, Matched %hu children (< MCAST_THRD), unicast the message. \n", 
							hdr->seqno, qe->cur_next_hop_idx);
							
			qe->retries = OSR_UCAST_RETRIES;
			hdr->next_hop = qe->next_hops[qe->cur_next_hop_idx - 1];
			hdr->option = OSR_UCAST;
			qe->pending_acks = qe->cur_next_hop_idx;
			
		}  else {// sink can broadcast
			dbg("OSR_Send", "seqno: %hu, broadcast the message, no child for next hop\n", hdr->seqno);
			qe->retries = OSR_BCAST_RETRIES;
			hdr->next_hop = 11111;	
			hdr->option = OSR_BCAST;
			call OsrInstrumentation.hlth_byp_init();
		}
		
		//// In sendTask, use the the hdr->option to find out whether to send to 
		//// bcast or unicast.
		
		/////// enqueue the packet
		
		dbg("OSR_Queue", "seqno: %d, OSR_Queue: %s: queue entry for %hhu is %hhu deep\n", hdr->seqno, __FUNCTION__, client, call SendQueue.size());
		if (call SendQueue.enqueue(qe) == SUCCESS) {
			if (hasState(RADIO_ON) && !hasState(SENDING)) {
				dbg("FHangBug", "%s posted sendTask.\n", __FUNCTION__);
				post sendTask();
			}
			clientPtrs[client] = NULL;
			return SUCCESS;
		}
		else {
			dbg("OSR_Queue", "seqno: %d, OSR_Queue: %s: send failed as packet could not be enqueued.\n", 
							hdr->seqno, __FUNCTION__);
      
			// Return the pool entry, as it's not for me...
			return FAIL;
		}
		
	}
	
	// Cancel a send request
	command error_t Send.cancel[uint8_t client](message_t* msg) {
		return FAIL;
	}
	
	// event to be signaled
	//	event void sendDone(message_t* msg, error_t error);

	command uint8_t Send.maxPayloadLength[uint8_t client]() {
		return call Packet.maxPayloadLength();
	}
	
	command void* Send.getPayload[uint8_t client](message_t* msg, uint8_t len) {
		return call Packet.getPayload(msg, len);
	}
	
	/* The actual send logic
	 *
	 */
	task void sendTask() {
		dbg("OSR_Task", "OSR_Task: %s: Trying to send a packet. Queue size is %hhu.\n", __FUNCTION__, call SendQueue.size());
		if (hasState(SENDING) || call SendQueue.empty()) {
			// dbg: Sending queue empty, or busy sending
			return;
		} else {
			error_t subsendResult = SUCCESS;
			osr_fe_queue_entry_t* qe = call SendQueue.head();
			osr_header_t* hdr = getHeader(qe->msg);
			
//			uint8_t payloadLen = call SubPacket.payloadLength(qe->msg);
			// MAC layer payload length = osr header + osr payload + osr tail
			// Osr tail = number of bytes in bflt, which is the path length
			uint8_t payloadLen = call Packet.payloadLength(qe->msg) + sizeof(osr_header_t) + sizeof(uint8_t)*hdr->path_len;
			
			dbg("OsrPayload", "seqno: %d, OsrPayload: Send Osr packet payload length: %d\n", hdr->seqno, payloadLen);
			
			
			// Debug FP
			// sink is not included in the path bflt
			// Record all the transmissions by the false positive node 
			if(TOS_NODE_ID != SINK_ADDR && is_fp_node(hdr->down_path, TOS_NODE_ID)) {
				dbg("TestFP", "seqno: %d, TestFP: Transmission caused by False positive node: %d\n", hdr->seqno, TOS_NODE_ID);
				call OsrInstrumentation.hlth_fp_tx();	// mcast_count caused by false positive
			}
			
			
			/// Send the packet either unicast or bcast
			
			if(hdr->option == OSR_UCAST) {
				// unicast
				dbg("OSR_Send", "seqno: %d, OSR_Send: Unicasting queue entry %p\n", hdr->seqno, qe);
				if (call PacketAcknowledgements.requestAck(qe->msg) == SUCCESS) {
					setState(ACK_PENDING);
				}
				call OsrInstrumentation.hlth_ucast_tx();	// total unicasts
				
				snoop_comlete = FALSE;
				subsendResult = call SubSend.send(qe->next_hops[qe->cur_next_hop_idx-1], qe->msg, payloadLen);
				
			} else if (hdr->option == OSR_MCAST || hdr->option == OSR_BCAST) {
				// bcast
				if (hdr->option == OSR_MCAST) {
					dbg("OSR_Send", "seqno: %d, OSR_Send: multicasting queue entry %p\n", hdr->seqno, qe);
					call OsrInstrumentation.hlth_mcast_tx();
				} else if (hdr->option == OSR_BCAST) {
					dbg("OSR_Send", "seqno: %d, OSR_Send: broadcasting queue entry %p\n", hdr->seqno, qe);
					call OsrInstrumentation.hlth_bcast_tx();
				}
				snoop_comlete = FALSE;
				subsendResult = call SubSend.send(AM_BROADCAST_ADDR, qe->msg, payloadLen);
			}
			
			if (subsendResult == SUCCESS) {
				// Successfully submitted to the data-link layer.
				setState(SENDING);
				dbg("OSR_Task", "seqno: %d, OSR_Task: %s: subsend succeeded with %p.\n", hdr->seqno, __FUNCTION__, qe->msg);
				return;
			} 
			else if(subsendResult == ESIZE) {
				// packet too large
				dbg("OSR_Task", "seqno: %d, OSR_Task: %s: subsend failed from ESIZE: truncate packet.\n", hdr->seqno, __FUNCTION__);
				call Packet.setPayloadLength(qe->msg, call Packet.maxPayloadLength());
				post sendTask();
			} 
			else {
				dbg("OSR_Task", "seqno: %d, OSR_Task: %s: subsend failed from %i\n", hdr->seqno, __FUNCTION__, (int)subsendResult);
			}
			
		}
	}
	
	/*
	 * The second phase of a send operation; based on whether the transmission was
	 * successful, the ForwardingEngine either stops sending or starts the
	 * RetxmitTimer with an interval based on what has occured. If the send was
	 * successful or the maximum number of retransmissions has been reached, then
	 * the ForwardingEngine dequeues the current packet. If the packet is from a
	 * client it signals Send.sendDone(); if it is a forwarded packet it returns
	 * the packet and queue entry to their respective pools.
	 * 
	 */
	void packetComplete(osr_fe_queue_entry_t* qe, message_t* msg, bool success) {
		osr_header_t* hdr = getHeader(msg);
		// Four cases:
 		// Local packet: success or failure
		// Forwarded packet: success or failure
		
		
		if (qe->client < CLIENT_COUNT) { 
			// local packets, basically only for the OSR Base station
			
			if(hdr->option == OSR_BCAST || hdr->option == OSR_MCAST){
				// If message is broadcasted, end the transmission 
				call SendQueue.dequeue();
				clearState(SENDING);
				clientPtrs[qe->client] = qe;
				// only the sender application needs the sendDone event
				signal Send.sendDone[qe->client](msg, SUCCESS);
				dbg("OSR_Bcast", "seqno: %d, OSR_Bcast: %s: packet for client %hhu bcasted DONE.\n",
											hdr->seqno, 
											__FUNCTION__, 
											qe->client);
				return;
			} 
			
			else {
				// all unicasts have been sent
				if(!success) {
					// if there is a failure during unicasting to any of the direct children 
					// perform opportunistic routing due to unicast fail
					
					qe->retries = OSR_BCAST_RETRIES;
					hdr->next_hop = 11111;	
					hdr->option = OSR_BCAST;
					dbg("OSR_Send", "seqno: %d, OSR_Send: Unicast failure, perform opportunistic routing\n", hdr->seqno);
					
					call OsrInstrumentation.hlth_byp_init_f();
					
//					startRetxTimer(OSR_UCAST_TO_BCAST_WINDOW, OSR_UCAST_TO_BCAST_OFFSET);
//					post sendTask();
					
				} else {
					// original process code, dequeue the packet, and signal sendDone
					call SendQueue.dequeue();
					clearState(SENDING);
					clientPtrs[qe->client] = qe;
					// only the sender application needs the sendDone event
					signal Send.sendDone[qe->client](msg, SUCCESS);
					if (success) {
						dbg("OSR_Send", "seqno: %d, OSR_Send: %s: packet for client %hhu acknowledged.\n", 
											hdr->seqno,
											__FUNCTION__, 
											qe->client);
					} else {
						dbg("OSR_Send", "seqno: %d, OSR_Send: %s: packet for client %hhu dropped.\n", 
											hdr->seqno,
											__FUNCTION__, 
											qe->client);
					}
				}
			
			
				
			}
			
		}
		else { 
			// forwarded packets
			// No matter success or fail, send the packet to the next matched children 
			// 
			if(hdr->option == OSR_BCAST || hdr->option == OSR_MCAST){
				// BCAST occurs only for opportunistic routing. 
				// When broadcast done, always return
				// 1. if a node receives Unicast, and 1) no matched children, 2) forwarding 
				// 		using Unicast fails
				// 2. if a node receives Multicast, and 1) forwarding using Unicast fails
				//
				// Multicast packets also does not care about ACKs, so return 
				call SendQueue.dequeue();
				clearState(SENDING);
				call MessagePool.put(qe->msg);
				call QEntryPool.put(qe);
				dbg("OSR_Bcast", "OSR_Bcast: %s: packet for client %hhu bcasted DONE.\n", 
											__FUNCTION__, 
											qe->client);
				return;
			}
			
//			osr_header_t* hdr = getHeader(msg);
//			qe->cur_next_hop_idx--;
//			if(qe->cur_next_hop_idx > 0) {
//				// there is another matched direct children to send 
//				qe->retries = OSR_UCAST_RETRIES;
//				hdr->next_hop = qe->next_hops[qe->cur_next_hop_idx-1];
////				post sendTask();
//				
//			} 
			else{
				// all unicast finished, broadcast this packet if necessary
				if(!success) {
					// If the packet is a Unicast failure, perform opportunistic routing
					// only when the packet is received from Unicast or Multicast
					// 
					if(qe->rcv_option != OSR_BCAST){
						// perform opportunistic routing 
						qe->retries = OSR_BCAST_RETRIES;
						hdr->next_hop = 11111;	
						hdr->option = OSR_BCAST;
						dbg("OSR_Send", "seqno: %d, OSR_Send: Unicast failure, perform opportunistic routing\n", hdr->seqno);
						call OsrInstrumentation.hlth_byp_init_f();
						
						// Debug FP
						// OPP performed by false positive nodes, this node must received unicast 

						if(TOS_NODE_ID != SINK_ADDR && is_fp_node(hdr->down_path, TOS_NODE_ID)) {
							dbg("TestFP", "seqno: %d, TestFP: OPP performed by False positive node %d due to unicast failure\n", hdr->seqno, TOS_NODE_ID);
							call OsrInstrumentation.hlth_fp_opp_init_f();	// 
						}
						
					}
					
//					startRetxTimer(OSR_UCAST_TO_BCAST_WINDOW, OSR_UCAST_TO_BCAST_OFFSET);
//					post sendTask();
					
				} else {
			
					call SendQueue.dequeue();
					clearState(SENDING);
					call MessagePool.put(qe->msg);
					call QEntryPool.put(qe);
				}
			}
	
		}
	
	}
	
	
	event void SubSend.sendDone(message_t* msg, error_t err) {
		// if the packet is already complete in Snoop, the queue would be empty
		// no need to process here 
		// TODO: in a frequent situation, the queue may not be empty
		if(snoop_comlete) {
			startRetxTimer(OSR_SENDDONE_OK_WINDOW, OSR_SENDDONE_OK_OFFSET);
			return;
		} else {
		
			osr_fe_queue_entry_t* qe = call SendQueue.head();
			osr_header_t* hdr = getHeader(msg);
			// TODO: current procedure is for unicast, add procedure for bcast 
			if(err != SUCCESS) {
				// sub layer send failed, resend
				dbg("OSR_Send", "OSR_Send: %s: send failed\n", __FUNCTION__);
				startRetxTimer(OSR_SENDDONE_FAIL_WINDOW, OSR_SENDDONE_FAIL_OFFSET);
			
			
			} else if(hdr->option == OSR_BCAST || hdr->option == OSR_MCAST) {
				// if this is a multicasted/broadcasted packet, 
				// retransmit if there are remaining transmissions.
				if(--qe->retries) {
					// extend the timer based on the remaining retries
					// The timer length: t, 2t, 3t, 4t, ...
					startRetxTimer(OSR_MCAST_WINDOW * (OSR_MCAST_RETRIES - qe->retries), 
									OSR_MCAST_OFFSET * (OSR_MCAST_RETRIES - qe->retries));
					dbg("OSR_Send", "seqno: %hu, OSR_Send sendDone: broadcast retry: (remaining retries: %d)\n", 
								hdr->seqno, qe->retries);
				} else {
					dbg("OSR_Send", "seqno: %hu, OSR_Send broadcast sendDone \n", 
							hdr->seqno);
						
					packetComplete(qe, msg, TRUE);
				}
			
			
			} else {
				// for Unicast case
				if(hasState(ACK_PENDING) && !call PacketAcknowledgements.wasAcked(msg)) {
					// NO ACK
			
					if(--qe->retries) {
						// retry
						call OsrInstrumentation.hlth_ucast_retx();
						startRetxTimer(OSR_SENDDONE_NOACK_WINDOW, OSR_SENDDONE_NOACK_OFFSET);
				
						dbg("OSR_Send", "seqno: %hu, OSR_Send sendDone: node %hu not acked, retry: (remaining retries: %d)\n", 
									hdr->seqno,  call AMPacket.destination(msg), qe->retries);
							
					} else {
						// Hit max retransmit threshold, use opportunistic routing
						// unicast failure, initialize a broadcast 

		//				call SendQueue.dequeue();
		//				clearState(SENDING);
				
						startRetxTimer(OSR_SENDDONE_FAIL_WINDOW, OSR_SENDDONE_FAIL_OFFSET);
				
						dbg("OSR_Send","seqno: %hu, OSR_Send sendDone: node %hu not acked, no more retries. Delivery FAILed\n", 
									hdr->seqno, call AMPacket.destination(msg));
							
						packetComplete(qe, msg, FALSE);
					}
				} else {
		//			osr_header_t* hdr = getHeader(msg);
					// packet was acknowledged
		//			call SendQueue.dequeue();
		//			clearState(SENDING);
					startRetxTimer(OSR_SENDDONE_OK_WINDOW, OSR_SENDDONE_OK_OFFSET);
			
					dbg("OSR_Send", "seqno: %hu, OSR_Send sendDone: packet SUCCESSFULLY deliveried to node %hu\n", 
								hdr->seqno,  call AMPacket.destination(msg));
						
					packetComplete(qe, msg, TRUE);
				}
			}
		}// out most else 
		
	}
	
	
	/* 
	 * Function for preparing a packet for forwarding. Performs a buffer swap from the 
	 * message pool.
	 */
	
	message_t* ONE forward(message_t* ONE m) {
		if(call MessagePool.empty()) {
			dbg("OSR_Send", "%s cannot forward, message pool empty. \n", __FUNCTION__);
		} else if (call QEntryPool.empty()) {
			dbg("OSR_Send", "%s cannot forward, queue entry pool empty. \n", __FUNCTION__);
		} else {
			message_t* newMsg;
			osr_fe_queue_entry_t* qe;
			osr_header_t* hdr = getHeader(m);
			osr_tail_t* tail = getTail(m, call Packet.payloadLength(m));
			bool id_found = FALSE;
			int i;
			
			qe = call QEntryPool.get();
			if(qe == NULL) {
				// error getting queue entry
				return m;
			}
			
			newMsg = call MessagePool.get();
			if(newMsg == NULL) {
				// error getting message pool 
				return m;
			}
			
			memset(newMsg, 0, sizeof(message_t));
			memset(m->metadata, 0, sizeof(message_metadata_t));
			
			qe->msg = m;
			qe->client = 0xff;		// oxff indicating this is a forwarded packet
			qe->rcv_option = hdr->option;
			
			// INSTRU: forward this packet to the next hop
			
			dbg("OSR_Receive", "seqno: %hu, OSR_Receive: ++++++++++ forward the packet: seqno: %d\n", hdr->seqno, hdr->seqno);
		 	qe->cur_next_hop_idx = 0;
			for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
				qe->next_hops[i] = 0;
			}
			// All reception types (ucast, mcast, and bcast), needs to do the check 
			for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
						
				if(children[i].id != 0) {
					int j;
					for(j = 0; j < MAX_BFLT_LEN; j++) {
						chd_bflt[j] = 0;
					}
				
					call BloomFilter.getBflt(children[i].id, chd_bflt, hdr->path_len);
					
					#if defined(PRINTF_OSR_ENABLED)  
					printf(" 	-- OSR Mote: compute bflt for child (%d, ttl: %d,i: %d) \n", 
										hdr->seqno, children[i].id, children[i].ttl, i);
					printfflush();
					#endif
				
					dbg("OSR_Receive", "seqno: %d, OSR_Receive: compute bflt for child (%hu, ttl: %hu, i: %hu) \n", 
									hdr->seqno, children[i].id, children[i].ttl, i);
				
					if(bfltMatched(chd_bflt, tail->path_bflt)) {
						qe->next_hops[qe->cur_next_hop_idx] = children[i].id;
						#if defined(PRINTF_OSR_ENABLED)  
						printf(" 	---- OSR Mote: matching child: %d \n", 
										children[i].id);
						printfflush();
						#endif
						qe->cur_next_hop_idx++;
					}
				
				}
			}
				
			dbg("OSR_Receive", "seqno: %hu, Children count: total children: %hu, included in the path: %hu children\n", 
					hdr->seqno, children_count, qe->cur_next_hop_idx);
			
			
			// Debug FP
			// for opportunistic routing, check whether it is delivered to a false positive child
			// false bypassing to a false positive node 
			if(qe->rcv_option == OSR_BCAST && qe->cur_next_hop_idx>0) {
				for(i = 0; i < qe->cur_next_hop_idx; i++) {
					if(is_fp_node(hdr->down_path, qe->next_hops[i])) {
						dbg("TestFP", "seqno: %d, TestFP: OPP acted to False Positive child: %d . False bypassing\n", hdr->seqno, qe->next_hops[i]);
						call OsrInstrumentation.hlth_fp_opp();	
						break;
					}
				}
			}
			
			// Debug FP
			// for normal forwarding, find the false positive matched children 
			if(qe->rcv_option != OSR_BCAST) {
				for(i = 0; i < qe->cur_next_hop_idx; i++) {
					if(is_fp_node(hdr->down_path, qe->next_hops[i])) {
						if(qe->cur_next_hop_idx > MCAST_THRD) {
							dbg("TestFP", "seqno: %d, TestFP: False positive caused multicast.\n", hdr->seqno);
							call OsrInstrumentation.hlth_mcast_count_fp();	// mcast_count caused by false positive
						} else {
							dbg("TestFP", "seqno: %d, TestFP: False positive caused unicast.\n", hdr->seqno);
							call OsrInstrumentation.hlth_ucast_count_fp();	// only one child, but false positive 
						}
						break;
					}
				}
			}
			
			if(qe->cur_next_hop_idx > MCAST_THRD){
				dbg("OSR_Receive", "seqno: %hu, Matched %hu children (> MCAST_THRD), multicast the message. \n", 
								hdr->seqno, qe->cur_next_hop_idx);
				qe->retries = OSR_MCAST_RETRIES;
				qe->pending_acks = qe->cur_next_hop_idx;
				hdr->next_hop = 22222;
				hdr->option = OSR_MCAST;
				
				snoop_comlete = FALSE;
				// INSTRU: forward this packet to the next hop
				call OsrInstrumentation.hlth_forwarded();
				call OsrInstrumentation.hlth_mcast_count();
				
				if(qe->rcv_option == OSR_BCAST) {
					// packet is received through broadcast, then it is an opportunistic routing 
					dbg("OSR_Receive", "seqno: %hu, act opportunistic routing, pkt received from broadcast. \n", 
									hdr->seqno);
					call OsrInstrumentation.hlth_byp_acted();
				}
				
			} else if (qe->cur_next_hop_idx > 0) {
				dbg("OSR_Receive", "seqno: %hu, Matched %hu children (< MCAST_THRD), unicast the message. \n", 
								hdr->seqno, qe->cur_next_hop_idx);
				qe->retries = OSR_UCAST_RETRIES;
				hdr->next_hop = qe->next_hops[qe->cur_next_hop_idx-1];
				hdr->option = OSR_UCAST;
				qe->pending_acks = qe->cur_next_hop_idx;
				
				snoop_comlete = FALSE;
				
				call OsrInstrumentation.hlth_forwarded();
				
				if(qe->rcv_option == OSR_BCAST) {
					// packet is received through broadcast, then act opportunistic routing 
					dbg("OSR_Receive", "seqno: %hu, act opportunistic routing, pkt received from broadcast. \n", 
									hdr->seqno);
					call OsrInstrumentation.hlth_byp_acted();
				}
				
			} else {
				// No children are found
				// or maybe the children is just gone, broadcast this packet can reach higher reception ratio
				// Opportunistic routing would never reach this branch, controlled in the SubReceive event
				
				// if the packet is received through Unicast, then perform opportunistic routing 
				if(qe->rcv_option == OSR_UCAST) {
					qe->retries = OSR_BCAST_RETRIES;
					hdr->next_hop = 11111;
					hdr->option = OSR_BCAST;
					dbg("OSR_Receive", "seqno: %hu, pkt received from unicast, no matched children, perform opportunistic routing. \n", 
								hdr->seqno);
					call OsrInstrumentation.hlth_forwarded();
					call OsrInstrumentation.hlth_byp_init();
					
					// Debug FP
					// OPP performed by false positive nodes, this node must received unicast 

					if(is_fp_node(hdr->down_path, TOS_NODE_ID)) {
						dbg("TestFP", "seqno: %d, TestFP: OPP performed by False positive node: %d due to no matched children\n", hdr->seqno, TOS_NODE_ID);
						call OsrInstrumentation.hlth_fp_opp_init();	// mcast_count caused by false positive
					}
					
					
				} else {
					// release the memory in pool, and return 
					dbg("OSR_Receive", "seqno: %hu, pkt received from multicast/broadcast, no matched children, ignore. \n", 
								hdr->seqno);
					call MessagePool.put(newMsg);
					call QEntryPool.put(qe);
					return m;
				}
//				
				
				//////////////////////// do not do opportunistic routing if no matched 
//				// release the memory in pool, and return 
//				dbg("OSR_Receive", "seqno: %hu, pkt received from multicast/broadcast, no matched children, ignore. \n", 
//							hdr->seqno);
//				call MessagePool.put(newMsg);
//				call QEntryPool.put(qe);
//				return m;
				
			}
			
			if(call SendQueue.enqueue(qe) == SUCCESS) {
				dbg("OSR_Send", "OSR_Send: %s forwarding packet %p with queue size %hhu\n", 
								__FUNCTION__, m, call SendQueue.size());
				
				if(!call RetxTimer.isRunning()) {
					// if the timer is running, the task is posted in the timer.fired()
					// otherwise, post it here.
					post sendTask();
				}
				
				return newMsg;
			} else {
				// error enqueuing the message 
				call MessagePool.put(newMsg);
				call QEntryPool.put(qe);
				
				dbg("OSR_Send", "OSR_Send: %s enqueue packet %p error with queue size %hhu\n", 
								__FUNCTION__, m, call SendQueue.size());
			}
			
		}
		
		return m;
	}
	
	/*
	 * Receive an OSR downstream packet, check the bloom filter, and decide whether 
	 * to forward it or not.
	 */
	
	event message_t* SubReceive.receive(message_t* msg, void* payload, uint8_t len) {
		osr_id_t osrid;
		osr_header_t* rcv_hdr = getHeader(msg);
		osr_tail_t* rcv_tail = getTail(msg,  call Packet.payloadLength(msg));
		int i;
		
//		dbg("OsrPayload", "OsrPayload: receive payload length: %d, call Packet.payloadLen(): %d, SubPacket.payloadLength(): %d\n", 
//									len, call Packet.payloadLength(msg), call SubPacket.payloadLength(msg));
		
		if(len > call SubSend.maxPayloadLength()) {
			return msg;
		}
	
		// filter duplicates
		if(hasSeen(rcv_hdr->seqno, rcv_hdr->rnd)) {
//			// if this is a duplicate packet, ignore it
//			dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: seqno: %d\n", rcv_hdr->seqno, rcv_hdr->seqno);
//			
//			//////// debug statement	
//			pre_parent = call AMPacket.source(msg);
//			call CtpInfo.getParent(&parent);
//			
//			if(rcv_hdr->option == OSR_UCAST){
//				if(pre_parent != parent) {
//					dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: unicast dup, retried unicast, parent_changed\n", rcv_hdr->seqno);
//				} else {
//					dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: unicast dup, retried unicast, parent_same\n", rcv_hdr->seqno);
//				}	
//			} else if(rcv_hdr->option == OSR_BCAST || rcv_hdr->option == OSR_MCAST) {
//				
//				// receive bcast packet, check whether it is due to unicast failure
//				if(rcv_hdr->next_hop == TOS_NODE_ID) {
//					// the bcast is due to unicast failure
//					// Check whether it has a parent change, this may cause unicast failure
//					if(pre_parent != parent) {
//						dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: bcast dup, unicast_failed, parent_changed\n", rcv_hdr->seqno);
//					}else {
//						dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: bcast dup, unicast_failed, parent_same\n", rcv_hdr->seqno);
//					}
//						
//				} else if (rcv_hdr->option == OSR_MCAST){
//					
//					dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: mcast dup, due to many children\n", rcv_hdr->seqno);
//				} else if (rcv_hdr->option == OSR_BCAST){
//					dbg("OSR_Receive", "seqno: %hu, OSR_Receive: duplicate packet: bcast dup, due to no children\n", rcv_hdr->seqno);
//					
//				} 

//			}
			//////////////////////////
			return msg;
		} 
		
		
		osrid = call OsrPacket.getType(msg);
		
		rcv_hdr->ttl--;	// decrease the ttl of the packet 
		
		dbg("OSR_TTL", "seqno: %d, OSR_TTL: packet ttl: %d\n", rcv_hdr->seqno, rcv_hdr->ttl);
		
		if(!call RootControl.isRoot()) {
			// if not CTP root, then update the seqno 
			seqno = rcv_hdr->seqno;
		}
		
		//////// debug statement
		// for TOTAL new packet bcast receive and unicast receive
		if(rcv_hdr->option == OSR_UCAST){
			dbg("OSR_Receive", "seqno: %hu, OSR_Receive: receive new packet: seqno: %d , unicast receive\n", rcv_hdr->seqno, rcv_hdr->seqno);
		} else if(rcv_hdr->option == OSR_BCAST){ 
			dbg("OSR_Receive", "seqno: %hu, OSR_Receive: receive new packet: seqno: %d , bcast receive \n", rcv_hdr->seqno, rcv_hdr->seqno);
		} else {
			dbg("OSR_Receive", "seqno: %hu, OSR_Receive: receive new packet: seqno: %d , mcast receive \n", rcv_hdr->seqno, rcv_hdr->seqno);
		}
		///////////////
		
		// not duplicate, update history
		insert(rcv_hdr->seqno, rcv_hdr->rnd);
		
		// if the application does not want to further forward the packet, ignore it
//		if (!signal Intercept.forward[osrid](msg, 
//						call Packet.getPayload(msg, call Packet.payloadLength(msg)), 
//						call Packet.payloadLength(msg))) {
//			return msg;		
//		} else {
			// receive or forward the packet 
			if(TOS_NODE_ID == rcv_hdr->target_id) {
				// packet reach the destination, signal the upper layer
				return signal Receive.receive[osrid](msg, 
								call Packet.getPayload(msg, call Packet.payloadLength(msg)),
								call Packet.payloadLength(msg));
			
			} else if(rcv_hdr->ttl > 0) {
				// the packet is still alive
				if(rcv_hdr->option == OSR_UCAST || rcv_hdr->option == OSR_BCAST) {
					// receive unicast, forward the packet 
					// if receive broadcast, forward the packet only there is matched children 
					// 		the check logic is in forward()
					return forward(msg);
//				} else if( rcv_hdr->option == OSR_BCAST) {
//					// receive broadcast packet, forward only if there is matched children 
//					// the logic is in forward() function 
//					return forward(msg);

				} else {
					// receive a multicast message, forward only if the Bflt matches 
					// compute local bloom filter based on the bflt length
					for(i = 0; i < MAX_BFLT_LEN; i++){
						my_bflt[i] = 0;
					}
					call BloomFilter.getBflt(TOS_NODE_ID, my_bflt, rcv_hdr->path_len);
		
					if(bfltMatched(my_bflt, rcv_tail->path_bflt)) {
						// Receive multicast, but Bflt not matched 
						// ignore the message 
						
						return forward(msg);
					} else {
						dbg("OSR_Receive", "seqno: %hu, OSR_Receive: bflt not match, ignore the packet \n", rcv_hdr->seqno, rcv_hdr->seqno);
					}
				}
				
			} else {
				dbg("OSR_TTL", "seqno: %d, OSR_TTL: packet ttl reaches 0: ttl: %d\n", rcv_hdr->seqno, rcv_hdr->ttl);
			}
		return msg;
			
//		}
			
	}
	
	event message_t* SubSnoop.receive(message_t* msg, void* payload, uint8_t len) {
		// if the packet is sending, if a received packet 1)has the same seqno 
		//		and 2) lower TTL, then the packet is been received by next hops.
		//		The node can cancel the current transmission 
		// Do this only for multicast or unicast packets.
		// Broadcast should be transmitted to the end.
		
		// TODO: Add overhead node to the children set if their ETX is 0.5 larger than mine.
		int i;
		dbg("OSR_Snoop", "OSR_Snoop: packet from %d\n", call AMPacket.source(msg));
		if(hasState(SENDING) && call SendQueue.size() > 0) {
			osr_fe_queue_entry_t* qe = call SendQueue.head();
			osr_header_t* rcv_hdr = getHeader(msg);
			osr_header_t* hdr = getHeader(qe->msg);
			
			dbg("OSR_Snoop", "OSR_Snoop: --\t check condition (rcv_id: %d)\n", call AMPacket.source(msg));
			
			if(rcv_hdr->ttl < hdr->ttl && hdr->seqno == rcv_hdr->seqno) {
				// the next hops along the path has already received this packet 
				dbg("OSR_Snoop", "OSR_Snoop: ----\t start to process: seqno: %d, my_ttl: %d, rcv_ttl: %d, (rcv_id: %d)\n", 
												rcv_hdr->seqno, hdr->ttl, rcv_hdr->ttl, call AMPacket.source(msg));
				if(hdr->option == OSR_UCAST) {
					// the children has received the packet, cancel current transmission 
					if(qe->next_hops[0] == call AMPacket.source(msg)) {
						snoop_comlete = TRUE;
						dbg("OSR_Snoop", "OSR_Snoop: --\t Unicast passive acked, seqno: %d, my_ttl: %d, rcv_ttl: %d, (rcv_id: %d)\n", 
												rcv_hdr->seqno, hdr->ttl, rcv_hdr->ttl, call AMPacket.source(msg));
												
						call OsrInstrumentation.hlth_snoop_ack();
						packetComplete(qe, msg, TRUE);
					}
					
				} else if(hdr->option == OSR_MCAST) {
					// for multicast packets, check whether the node is acked based 
					// on the qe->next_hops array
					
					for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
						if(qe->next_hops[i] == call AMPacket.source(msg)) {
							// find the matched next hops, mark it as acked (remove it)
							qe->next_hops[i] = 0;
							
							qe->pending_acks--;
							dbg("OSR_Snoop", "OSR_Snoop: --\t Mcast passive acked, seqno: %d, my_ttl: %d, rcv_ttl: %d, remaining acks: %d, (rcv_id: %d)\n", 
												rcv_hdr->seqno, hdr->ttl, rcv_hdr->ttl, qe->pending_acks, call AMPacket.source(msg));
							
							
							break;
						}
					}
					// if all the nodes in the next_hops are acked, stop current transmission 
					if(qe->pending_acks <= 0) {
						dbg("OSR_Snoop", "OSR_Snoop: --\t Mcast passive acked ALL, seqno: %d, my_ttl: %d, rcv_ttl: %d, remaining acks: %d, (rcv_id: %d)\n", 
												 rcv_hdr->seqno, hdr->ttl, rcv_hdr->ttl, qe->pending_acks, call AMPacket.source(msg));
						snoop_comlete = TRUE;
						
						call OsrInstrumentation.hlth_snoop_ack();
						packetComplete(qe, msg, TRUE);
					}
					
				}
			}
		}
//		
		return signal Snoop.receive[call OsrPacket.getType(msg)] (msg,
				payload + sizeof(osr_header_t),
				call Packet.payloadLength(msg));
		
	}
	
	event void RetxTimer.fired() {
		clearState(SENDING);
		post sendTask();
	}
	
	/************************** Intercept *************************************/
	// Intercept Ctp packet to update the children table
	event bool Intercept.forward[collection_id_t collectionid](message_t* msg, void* payload, uint8_t len){
		uint16_t child = call AMPacket.source(msg);
//		uint8_t hopCounter = call CtpPacket.getThl(msg);
//		bool found = FALSE;
		
		call ChildrenTable.update(child); 
		//	
		// record the direct children
		//
/*		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			if(children[i].id == child) {
				// the child is already stored
				found = TRUE;
				children[i].ttl = MAX_CHILD_TTL;
				break;
			}
		}
		if(!found) {
			// find an empty slot
			// If no empty slot is found, replace the last one
			// TODO: a better way to find the empty slot
			for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
				if(children[i].id == 0) {
					child_idx = i;
					break;
				}
			}
			
			// add this child to an empty slot
			children[child_idx].id = child;
			children[child_idx].ttl = MAX_CHILD_TTL;
			child_idx++;
			child_idx %= OSR_CHILDREN_SIZE;
			children_count++;
			dbg("Children","Children Add child: %hu\n", child);
		}
	*/	
		return TRUE;
	}
	
	/************************** OsrPacket commands ****************************/
	// Bflt is computed by the application 
	// TODO: put the path_bflt to the tail 
	command void OsrPacket.setPathBflt(message_t* msg, nx_uint8_t* bflt) {
//		osr_header_t* hdr = getHeader(msg);
		osr_tail_t* tail = getTail(msg, call Packet.payloadLength(msg));
		int i;
		for(i = 0; i < MAX_BFLT_LEN; i++) {
//			hdr -> path_bflt[i] = bflt[i];
			tail -> path_bflt[i] = bflt[i];
		}

	}
	command void OsrPacket.getPathBflt(message_t* msg, nx_uint8_t* bflt){
//		osr_header_t* hdr = getHeader(msg);
//		bflt = hdr->path_bflt;
		osr_tail_t* tail = getTail(msg, call Packet.payloadLength(msg));
		bflt = tail->path_bflt;
	}
	
	
	command void OsrPacket.setDestination(message_t* msg, uint16_t targetId) {
		osr_header_t* hdr = getHeader(msg);
		hdr->target_id = targetId;
	}
	command uint16_t OsrPacket.getDestination(message_t* msg) {
		return getHeader(msg) -> target_id;
	}
	
	command void OsrPacket.setSeqno(message_t* msg, uint8_t seq) {
		osr_header_t* hdr = getHeader(msg);
		hdr->seqno = seq;
	}
	command uint16_t OsrPacket.getSeqno(message_t* msg) {
		return getHeader(msg)->seqno;
	}
	
	command uint8_t OsrPacket.getRnd(message_t* msg) {
		return getHeader(msg)->rnd;
	}
	
	command void OsrPacket.setType(message_t* msg, osr_id_t type) {
		osr_header_t* hdr = getHeader(msg);
		hdr->type = type;
	}
	command osr_id_t OsrPacket.getType(message_t* msg) {
		return getHeader(msg)->type;
	}
	
	command void OsrPacket.setPathLen(message_t* msg, uint8_t len) {
		osr_header_t* hdr = getHeader(msg);
		hdr->path_len = len;
	}
	
	command uint8_t OsrPacket.getPathLen(message_t* msg) {
		return getHeader(msg)->path_len;
	}
	
	
//	command void OsrPacket.setDownPath(message_t* msg, uint16_t* down_path) {
	command void OsrPacket.setDownPath(message_t* msg, uint8_t* down_path) { // Modified for Indriya to save RAM
		osr_header_t* hdr = getHeader(msg);
		int i;
		for(i = 0; i < MAX_PATH_LEN; i++) {
			hdr -> down_path[i] = down_path[i];
		}
	}
	
	
/*	
	command void OsrPacket.setBfltHashNum(uint8_t num) {
		
	}
	command void OsrPacket.setBfltLength(uint8_t len) {
		
	}
*/
	/******************************* Packet commands **************************/
	command void Packet.clear(message_t* msg) {
		call SubPacket.clear(msg);
	}
	
	
	// get the payload length of the packet 
	command uint8_t Packet.payloadLength(message_t* msg) {
		osr_header_t* hdr = getHeader(msg);
		uint8_t payloadLen = call SubPacket.payloadLength(msg) - sizeof(osr_header_t) - sizeof(uint8_t)*hdr->path_len;
		
//		dbg("OsrPayload", "OsrPayload: subPacketLen: %d, payload length is: %d)\n", 
//								call SubPacket.payloadLength(msg), payloadLen);
		return payloadLen;
	}

	command void Packet.setPayloadLength(message_t* msg, uint8_t len) {
		osr_header_t* hdr = getHeader(msg);
		call SubPacket.setPayloadLength(msg, len + sizeof(osr_header_t) + sizeof(uint8_t)*hdr->path_len);
	}
  
	command uint8_t Packet.maxPayloadLength() {
		return call SubPacket.maxPayloadLength() - sizeof(osr_header_t) - sizeof(osr_tail_t);
	}

	command void* Packet.getPayload(message_t* msg, uint8_t len) {
		uint8_t* payload = call SubPacket.getPayload(msg, len + sizeof(osr_header_t));
		if (payload != NULL) {
			payload += sizeof(osr_header_t);
		}
		return payload;
	}
	
	/**************************** ChildrenTable commands **********************/
	command void ChildrenTable.update(uint16_t child) {
		bool found = FALSE;
		int i;
		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			if(children[i].id == child) {
				// the child is already stored
				found = TRUE;
				children[i].ttl = MAX_CHILD_TTL;
				break;
			}
		}
		if(!found) {
			bool table_full = TRUE;
			// find an empty slot
			// If no empty slot is found, replace the last one
			// TODO: a better way to find the empty slot
			for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
				if(children[i].id == 0) {
					table_full = FALSE;
					child_idx = i;
					break;
				}
			}
			
			if (table_full) {
				// table is full, replace the children with the lowest ttl 
				int minTtl = MAX_CHILD_TTL;
				int replace_idx = -1;
				for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
					if(children[i].ttl < minTtl) {
						minTtl = children[i].ttl;
						replace_idx = i;
					}
				}
				if(replace_idx > -1) {
					// replace this children with current id 
					children[replace_idx].id = child;
					children[replace_idx].ttl = MAX_CHILD_TTL;
					dbg("Children","------ Children Add child: %hu\n", child);
				}
				else {
					// cannot be put in the table, print error 
					dbg("OsrError", "OsrError: table full, cannot add child: %d\n", child);
				}
				
			} else {
				// add this child to an empty slot
				children[child_idx].id = child;
				children[child_idx].ttl = MAX_CHILD_TTL;
				child_idx++;
				child_idx %= OSR_CHILDREN_SIZE;
				children_count++;
				dbg("Children","------ Children Add child: %hu\n", child);
			}
			
			
		}
	}
	
	command void ChildrenTable.decreaseTtl() {
		// decrease the ttl of all the children 
		int i;
		for(i = 0; i < OSR_CHILDREN_SIZE; i++) {
			children[i].ttl--;
			if(children[i].ttl <= 0) {
				children[i].ttl = 0;
				children[i].id = 0;
			}
			if(children_count > 0){
				children_count--;
			}
			dbg("Children","-------- Children table: child: %hu, ttl: %d\n", children[i].id, children[i].ttl);
		}
	}
	
	void clearState(uint8_t state) {
		forwardingState = forwardingState & ~state;
	}
	
	bool hasState(uint8_t state) {
		return forwardingState & state;
	}
	
	void setState(uint8_t state) {
		forwardingState = forwardingState | state;
	}
	
	
	/******************************** Defaults ********************************/
	default event void Send.sendDone[uint8_t client](message_t *msg, error_t error) { }
	
	default event message_t * Receive.receive[osr_id_t osrid](message_t *msg, void *payload, uint8_t len) {
		return msg;
	}
//	default event bool Intercept.forward[osr_id_t osrid](message_t* msg, void* payload, uint8_t len) {
//		return TRUE;
//	}
	
	default event message_t * Snoop.receive[osr_id_t osrid](message_t *msg, void *payload, uint8_t len) {
		return msg;
	}
	
	default command osr_id_t OsrId.fetch[uint8_t client]() {
		return 0;
	}
}
