/*
 * Given a node id, return the bloom filter with the corresponding bit set.
 * The gateway must have the same code to generate the same Bloom Filter.
 * 
 * @author 	Xiaoyang Zhong
 * @date	2016-04-02
 */

#include "BloomFilter.h"
//#include "fnv.h"

module BloomFilterP {
	provides interface BloomFilter;
}
implementation{
	/*
	 * Implementation of Thomas Wang's integer hash function
	 * https://gist.github.com/badboy/6267743
	 * https://naml.us/blog/tag/thomas-wang
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *			   the node id.
	 *
	 * @return 64 bit hash value
	 */
	
	uint8_t ret[BFLT_H] = {0};
	uint32_t seed = 0;

	uint32_t hval[BFLT_H] = {0};

	uint64_t t = 1;
	uint8_t bit = 0;	// the bit position in the BFLT_MAXL
	uint8_t byte_idx = 0;	// the byte index in the actual bflt array
	uint8_t bit_position = 0;	// the bit position in the actual bflt array target byte
	
	uint64_t key = 0;	// for twhash64
	uint32_t a = 0;		// for bjhash32
	uint64_t hval_fnv = 0;	// for fNV
	
	uint64_t twhash64(uint64_t buf) {
		key = buf;
		key = (~key) + (key << 21); // key = (key << 21) - key - 1;
		key = key ^ (key >> 24);
		key = (key + (key << 3)) + (key << 8); // key * 265
		key = key ^ (key >> 14);
		key = (key + (key << 2)) + (key << 4); // key * 21
		key = key ^ (key >> 28);
		key = key + (key << 31);
		return key;
	}

	/*
	 * Implementation of Bob Jenkins's integer hash function
	 * http://burtleburtle.net/bob/hash/integer.html
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *			   the node id.
	 *
	 * @return 32 bit hash value
	 */
	uint32_t bjhash32( uint32_t buf)
	{
		a = buf;
		a -= (a<<6);
		a ^= (a>>17);
		a -= (a<<9);
		a ^= (a<<4);
		a -= (a<<3);
		a ^= (a<<10);
		a ^= (a>>15);
		return a;
	}
	
	/////// This function would cause Interval compilation error in TelosB mote
	/////// So, don't use it
	/*
	 * Implementation of 64-bit FNV1-a hash
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *			   the node id.
	 *		  len: the size of the buffer. In this application, it is always 2.
	 * @return 64 bit hash value
	 */
	
//	uint64_t fnv64ahash(void* buf, uint8_t len){
//	
//		unsigned char *bp = (unsigned char *)buf;	//start of buffer
//		unsigned char *be = bp + len;		// beyond end of buffer 

//		hval_fnv = FNV_64_INIT;
//	
//		while (bp < be) {
//			// xor the bottom with the current octet 
//			hval_fnv ^= (uint8_t)*bp++;
//		
//			// multiply by the 32 bit FNV magic prime mod 2^32 
//			hval_fnv *= FNV_64_PRIME;			////////////////////////////compilation error with TelosB platform

//		};

//		// %llu indicates long long unsigned integer
////		dbg("BloomFilterC", "BloomFilterC: hash value is: %llu\n", hval);
//		// return the hash value 
//		return hval_fnv;
//		
//	
//	}
	
	
	/*
	 * Implementation of 32-bit FNV1-a hash
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *			   the node id.
	 *		  len: the size of the buffer. In this application, it is always 2.
	 * @return 32 bit hash value
	 */

	uint32_t fnv32ahash(void* buf, uint8_t len){
	
		unsigned char *bp = (unsigned char *)buf;	//start of buffer
		unsigned char *be = bp + len;		// beyond end of buffer 

		hval_fnv = FNV_32_INIT;
	
		while (bp < be) {
			// xor the bottom with the current octet 
			hval_fnv ^= (uint8_t)*bp++;
		
			// multiply by the 32 bit FNV magic prime mod 2^32 
			hval_fnv *= FNV_32_PRIME;
		};

		// return the hash value 
		return hval_fnv;
	
	}
	
	
	/*
	 * Given a node id, return the bloom filter with the bits set
	 * 
	 * @param 	id: the AM address, 16-bit integer
	 *			buf: the buf to store 128 bits bflt value, it is two 64-bits integer
	 */
	command void BloomFilter.getBflt(uint16_t id, nx_uint8_t* bflt, uint8_t bflt_len) {
		// 
		uint8_t actual_len = bflt_len*8;
		uint8_t org_bits[BFLT_H];
		int i;
		seed = (uint32_t)id*10000 + (uint32_t) (0xfffff+1001);
		
		for(i = 0; i < BFLT_H; i++){
			hval[i] = 0;
		}
		
		hval[0] = (uint32_t) fnv32ahash(&seed, 4);	// 2 is the number of bytes in id
		hval[1] = (uint32_t) twhash64((uint64_t)seed);	// 2 is the number of bytes in id
		hval[2] = bjhash32(seed);
		
//		dbg("BloomFilterC", "BloomFilterC: hval1: %llu, hval1: %llu, hval2: %llu\n", 
//									hval[0], hval[1], hval[2]);
		
		for(i = 0; i < BFLT_H; i++) {
			t = 1;
			bit = 0;
			org_bits[i] = 0;
			bit = hval[i] % BFLT_MAXL;	
			
			/* The actual length of the bloom filter is "bflt_len * 8"
			 * To map the "bit" in range (0, BFLT_MAXL) to an actual byte in "bflt",
			 * Two values needs to be defined:
			 *	1. the byte index: e.g., the 0th byte, the 1st byte 
			 * 	2. the position in the byte 
			 * 
			 **/						
			// for debug 
			
			org_bits[i] = bit;
			
			bit = bit % actual_len;		// the bit position in actual blft
			byte_idx = bit / 8;			// the byte index
			bit_position = bit % 8;		// the bit position in the byte 
			bflt[byte_idx] = bflt[byte_idx] | (1 << bit_position);
			
			dbg("BloomFilterC", "BloomFilterC: id: %d, bflt_len: %d, actual bit: %d, byte_idx: %d, bit_position: %d\n", 
									id, bflt_len, bit, byte_idx, bit_position);
			
		}
		
		dbg("BloomFilterC", "BloomFilterC: the original bit to be set is:\t%d\t%d\t%d\n", org_bits[0], org_bits[1], org_bits[2]);
	
	//	#if defined(PRINTF_OSR_ENABLED)  
	//		printf("              ---OSR Mote: BloomFilterC: the bit to be set is:\t%d\t%d\t%d\n", ret[0], ret[1], ret[2]);
	//		printfflush();
	//	#endif
				
	}

}
