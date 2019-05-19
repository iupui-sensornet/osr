
interface OsrInstrumentation {
	command error_t init() ;

	command error_t summary(nx_uint8_t *buf);


	command uint8_t summary_size();

	command error_t hlth_forwarded();
	command uint16_t get_hlth_forwarded();

	command error_t hlth_byp_init();		// OPP performed due to no matched children
	command uint16_t get_hlth_byp_init();	
		
	command error_t hlth_byp_init_f();		// OPP performed due to unicast failure
	command uint16_t get_hlth_byp_init_f();
	
	command error_t hlth_byp_acted();
	command uint16_t get_hlth_byp_acted();
	
	command error_t hlth_ucast_retx();	// unicast retx
	command uint16_t get_hlth_ucast_retx();
	
	command error_t hlth_ucast_tx();	// unicast all tx
	command uint16_t get_hlth_ucast_tx();
	
	command error_t hlth_mcast_tx();	// mcast all
	command uint16_t get_hlth_mcast_tx();
	
	command error_t hlth_bcast_tx();	// all bcast
	command uint16_t get_hlth_bcast_tx();
	
	command error_t hlth_mcast_count();	// all number of times has multiple matched children  
	command uint16_t get_hlth_mcast_count();
	
	command error_t hlth_snoop_ack();	// all number of times has multiple matched children  
	command uint16_t get_hlth_snoop_ack();
	
//	command error_t hlth_snoop_ack();	// all number of times has multiple matched children  
//	command uint16_t get_hlth_snoop_ack();

	command error_t hlth_mcast_count_fp();	// FP caused multicast to multiple matched children 
	command uint16_t get_hlth_mcast_count_fp();
	
	command error_t hlth_ucast_count_fp();	// FP caused unicast to only one children 
	command uint16_t get_hlth_ucast_count_fp();
	
	command error_t hlth_fp_tx();	// FP caused multicast to multiple matched children 
	command uint16_t get_hlth_fp_tx();
	
	command error_t hlth_fp_opp();			// OPP acted to False positive node (False bypassing)
	command uint16_t get_hlth_fp_opp();
	
	command error_t hlth_fp_opp_init();			// OPP performed by false positive node (no matched children)
	command uint16_t get_hlth_fp_opp_init();	
	
	command error_t hlth_fp_opp_init_f();		// OPP performed by false positive node due to unicast failure
	command uint16_t get_hlth_fp_opp_init_f();
}
