/*
 * Copyright (c) 2016 Indiana University Purdue University Indianapolis
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 *
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

 /*
	* Author: Xiaoyang Zhong
  */

module OsrInstrumentationP {
  provides interface OsrInstrumentation;
}

implementation {

  typedef nx_struct StatCounters {
    nx_uint16_t fwd_count;		// total forwards, including normal fwd and bypassing 
    							// this means, a node has forwarded the packet further
    nx_uint16_t byp_init;		// opportunistic routing due to no children
    nx_uint16_t byp_init_f;		// opportunistic routing due to unicast failure
    nx_uint16_t byp_acted;		// the bypassing performed by a bcast receiver
    nx_uint16_t ucast_retx;		// unicast retx
    nx_uint16_t ucast_tx;		// including retx
    nx_uint16_t mcast_tx;		// all mulcasts
    nx_uint16_t bcast_tx;		// all bcasts 
    nx_uint16_t mcast_count;	// the number of times has multiple matched children 
	nx_uint16_t snoop_ack;		// the complete acks received from Snoop
								// 1. for Unicast, one ack is enough
								// 2. for Multicast, all acks should be received to increase this counter
								
	nx_uint16_t mcast_count_fp;	// FP caused multiple matched children 
	nx_uint16_t ucast_count_fp;	// FP caused unicast to only one false positive children 
	nx_uint16_t fp_tx;			// all transmissions caused by nodes not along the path
	nx_uint16_t fp_opp;			// OPP delivered to False positive node (False bypassing)
								//		A node acts OPP (after receiving bcast), but the packet is for a false postive child 
								//		for True bypassing, a node acts OPP (after receiving bcast), and deliver to packet to true child
	nx_uint16_t fp_opp_init;	// OPP performed by false positive node (no matched children)
	nx_uint16_t fp_opp_init_f;	// OPP performed by false positive node due to unicast failure
  } StatCounters;

  StatCounters stats;

  command error_t OsrInstrumentation.init() {
    stats.fwd_count = 0;
    stats.byp_init = 0;
    stats.byp_init_f = 0;
    stats.byp_acted = 0;
    stats.ucast_retx = 0;
    stats.ucast_tx = 0;
    stats.bcast_tx = 0;
    stats.mcast_tx = 0;
    stats.mcast_count = 0;
	stats.snoop_ack = 0;
	
	stats.mcast_count_fp = 0;	// FP caused multiple matched children 
	stats.ucast_count_fp = 0;	// FP caused unicast to only one children 
	stats.fp_tx = 0;			// All transmissions from nodes not in the path, including the false positives
								//		----- all transmission caused by false positive nodes 
	stats.fp_opp = 0;			// OPP delivered to False positive node (False bypassing)
	stats.fp_opp_init = 0;		// OPP performed by false positive node (no matched children) Ucast receive 
	stats.fp_opp_init_f = 0;	// OPP performed by false positives
	
    return SUCCESS;

  }
    
  command error_t OsrInstrumentation.summary(nx_uint8_t *buf) {
    memcpy(buf, &stats, sizeof(StatCounters));
    return SUCCESS;
  }


  command uint8_t OsrInstrumentation.summary_size() {
    return sizeof(StatCounters);
  }

  command error_t OsrInstrumentation.hlth_forwarded() {
    stats.fwd_count++;
    return SUCCESS;
  }
	command uint16_t OsrInstrumentation.get_hlth_forwarded(){
		return stats.fwd_count;
	}

	command error_t OsrInstrumentation.hlth_ucast_retx(){
		// unicast retx
		stats.ucast_retx++;
    	return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_ucast_retx(){
		return stats.ucast_retx;
	}
	
	command error_t OsrInstrumentation.hlth_ucast_tx(){
		// unicast retx
		stats.ucast_tx++;
    	return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_ucast_tx(){
		return stats.ucast_tx;
	}

	command error_t OsrInstrumentation.hlth_byp_init() {
		stats.byp_init++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_byp_init() {
		return stats.byp_init;
	}
	
	command error_t OsrInstrumentation.hlth_byp_init_f() {
		stats.byp_init_f++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_byp_init_f() {
		return stats.byp_init_f;
	}
	
	command error_t OsrInstrumentation.hlth_byp_acted() {
		stats.byp_acted++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_byp_acted() {
		return stats.byp_acted;
	}
	
	command error_t OsrInstrumentation.hlth_mcast_tx(){
		// multicast due to many children 
		stats.mcast_tx++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_mcast_tx() {
		return stats.mcast_tx;
	}
	
	
	command error_t OsrInstrumentation.hlth_bcast_tx(){
		// multicast due to many children 
		stats.bcast_tx++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_bcast_tx() {
		return stats.bcast_tx;
	}
	
	command error_t OsrInstrumentation.hlth_mcast_count(){
		// multicast due to many children 
		stats.mcast_count++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_mcast_count() {
		return stats.mcast_count;
	}
  
  	command error_t OsrInstrumentation.hlth_snoop_ack(){
		stats.snoop_ack++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_snoop_ack() {
		return stats.snoop_ack;
	}
	
	// for false positives
	command error_t OsrInstrumentation.hlth_ucast_count_fp(){
		stats.ucast_count_fp++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_ucast_count_fp() {
		return stats.ucast_count_fp;
	}
	
	command error_t OsrInstrumentation.hlth_mcast_count_fp(){
		stats.mcast_count_fp++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_mcast_count_fp() {
		return stats.mcast_count_fp;
	}
	
	command error_t OsrInstrumentation.hlth_fp_tx(){
		stats.fp_tx++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_fp_tx() {
		return stats.fp_tx;
	}
	
	command error_t OsrInstrumentation.hlth_fp_opp(){
		stats.fp_opp++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_fp_opp() {
		return stats.fp_opp;
	}
	
	command error_t OsrInstrumentation.hlth_fp_opp_init(){
		stats.fp_opp_init++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_fp_opp_init() {
		return stats.fp_opp_init;
	}
	
	command error_t OsrInstrumentation.hlth_fp_opp_init_f(){
		stats.fp_opp_init_f++;
		return SUCCESS;
	}
	command uint16_t OsrInstrumentation.get_hlth_fp_opp_init_f() {
		return stats.fp_opp_init_f;
	}
	
 
}

