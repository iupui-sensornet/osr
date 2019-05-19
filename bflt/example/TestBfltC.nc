/*
 * Test application of the bloom filter
 * 
 * @author 	Xiaoyang Zhong
 * @date	2016-4-2
 */
 
 #include "BloomFilter.h"
 
 #define TEST_BFLT_LEN 16
 
 module TestBfltC {
 	uses interface Boot;
 	uses interface BloomFilter;
 	uses interface Timer<TMilli>;
 }
 implementation {

 	nx_uint8_t bflt_buf[TEST_BFLT_LEN] = {0};
 	nx_uint8_t test_buf[TEST_BFLT_LEN] = {0};
 	uint8_t bflt_len =5;	// the actual number of bytes in a bflt 
 	uint16_t path[3] = {55, 47, 41};
 	
 	
 	/*
	 * Check whether the bflt1 is contained in bflt2
	 */
	bool bfltMatched(nx_uint8_t* bflt1, nx_uint8_t* bflt2){
		uint16_t j;

		for(j = 0; j < TEST_BFLT_LEN; j++) {
			dbg("TestMatch", "TestMatch: j: %d, Bflt1: %d, Bflt2: %d\n", j, bflt1[j], bflt2[j]);
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
 	

 	event void Boot.booted() {
 		uint16_t i, j;
 		
 		for( i=0; i < 300; i++) {
 		
 			call BloomFilter.getBflt(i, bflt_buf, bflt_len);
 			
 			dbg("TestBfltC", "TestBfltC: id: %d , bflt0: %d, bflt1: %d, bflt2: %d, bflt3: %d, bflt4: %d, bflt5: %d, bflt6: %d, bflt7: %d\n\n", 
 								i, bflt_buf[0], bflt_buf[1], bflt_buf[2], bflt_buf[3], 
 								bflt_buf[4], bflt_buf[5], bflt_buf[6], bflt_buf[7]);
 			
//			for(j = 0; j < TEST_BFLT_LEN; j++) {
//				if(j >= bflt_len && bflt_buf[j] > 0) {
//					dbg("TestBfltC", "TestBfltC: Error! Bflt value larger than expected!\n");
//				}
//				
//				bflt_buf[j] = 0;
////				dbg("TestBfltC", "TestBfltC: reset current value j: %d , bflt[j]: %d\n", 
//// 								j, bflt_buf[j]);
//			}
//			dbg("TestBfltC", "TestBfltC: reset values: bflt0: %d, bflt1: %d, bflt2: %d, bflt3: %d, bflt4: %d, bflt5: %d, bflt6: %d, bflt7: %d\n\n", 
// 								bflt_buf[0], bflt_buf[1], bflt_buf[2], bflt_buf[3], 
// 								bflt_buf[4], bflt_buf[5], bflt_buf[6], bflt_buf[7]);
			
 		}
 		call Timer.startOneShot(1024);
 		
 		call BloomFilter.getBflt(83, test_buf, bflt_len);
 		dbg("TestBfltC", "TestBfltC: id:83 , bflt0: %d, bflt1: %d, bflt2: %d, bflt3: %d, bflt4: %d, bflt5: %d, bflt6: %d, bflt7: %d\n\n", 
 								test_buf[0], test_buf[1], test_buf[2], test_buf[3], 
 								test_buf[4], test_buf[5], test_buf[6], test_buf[7]);
 		
 		
 		bfltMatched(test_buf, bflt_buf);
 		
 		
 		for(i = 0; i < TEST_BFLT_LEN; i++) {
 			test_buf[i] = 0;
 		}
 		
 		call BloomFilter.getBflt(71, test_buf, bflt_len);
 		dbg("TestBfltC", "TestBfltC: id:71 , bflt0: %d, bflt1: %d, bflt2: %d, bflt3: %d, bflt4: %d, bflt5: %d, bflt6: %d, bflt7: %d\n\n", 
 								test_buf[0], test_buf[1], test_buf[2], test_buf[3], 
 								test_buf[4], test_buf[5], test_buf[6], test_buf[7]);
 		
 		bfltMatched(test_buf, bflt_buf);
 		
 	}
 	event void Timer.fired() {
 		// sim_time_string() returns time in the format hr:min:sec.micro
 		dbg("TimerC", "timer fired at time: %s\n", sim_time_string());
 	}
 }
