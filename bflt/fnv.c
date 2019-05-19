/*
 * An implementation of FNV hash function
 *
 * @author Xiaoyang Zhong
 */
 
//#include <stdlib.h>
#include "fnv.h"


#define FNV_32_PRIME 0x01000193
#define FNV_32_INIT 0x811c9dc5

#define FNV_64_PRIME 0x100000001b3
#define FNV_64_INIT 0xcbf29ce484222325

/*
 * Implementation of 32-bit FNV1 hash
 
 * @param buf: The seed to generate the hash value. In this application, it is 
 *			   the node id.
 *		  len: the size of the buffer. In this application, it is always 2.
 * @return 32 bit hash value
 */

uint32_t fnv32hash(void* buf, uint8_t len){
	
	unsigned char *bp = (unsigned char *)buf;	//start of buffer
//  unsigned char *be = bp + len;		// beyond end of buffer 
    unsigned char *be = bp + 2;		// len always equals to 2 in this application 
	uint32_t hval = FNV_32_INIT;
	
	while (bp < be) {

		// multiply by the 32 bit FNV magic prime mod 2^32 
		hval *= FNV_32_PRIME;

		// xor the bottom with the current octet 
		hval ^= (uint8_t)*bp++;
    };

    // return the hash value 
    return hval;
	
}
	
/*
 * Implementation of 32-bit FNV1-a hash
 
 * @param buf: The seed to generate the hash value. In this application, it is 
 *			   the node id.
 *		  len: the size of the buffer. In this application, it is always 2.
 * @return 32 bit hash value
 */

uint32_t fnv32ahash(void* buf, uint8_t len){
	
	unsigned char *bp = (unsigned char *)buf;	//start of buffer
//  unsigned char *be = bp + len;		// beyond end of buffer 
    unsigned char *be = bp + 2;		// len always equals to 2 in this application 
	uint32_t hval = FNV_32_INIT;
	
	while (bp < be) {
		// xor the bottom with the current octet 
		hval ^= (uint8_t)*bp++;
		
		// multiply by the 32 bit FNV magic prime mod 2^32 
		hval *= FNV_32_PRIME;
    };

    // return the hash value 
    return hval;
	
}


/*
 * Implementation of 64-bit FNV1 hash
 
 * @param buf: The seed to generate the hash value. In this application, it is 
 *			   the node id.
 *		  len: the size of the buffer. In this application, it is always 2.
 * @return 64 bit hash value
 */

uint64_t fnv64hash(void* buf, uint8_t len){
	
	unsigned char *bp = (unsigned char *)buf;	//start of buffer
//  unsigned char *be = bp + len;		// beyond end of buffer 
    unsigned char *be = bp + 2;		// len always equals to 2 in this application 
	uint64_t hval = FNV_64_INIT;
	
	while (bp < be) {
		// multiply by the 32 bit FNV magic prime mod 2^32 
		hval *= FNV_64_PRIME;
		
		// xor the bottom with the current octet 
		hval ^= (uint8_t)*bp++;
		
    };

    // return the hash value 
    return hval;
	
}

/*
 * Implementation of 64-bit FNV1-a hash
 
 * @param buf: The seed to generate the hash value. In this application, it is 
 *			   the node id.
 *		  len: the size of the buffer. In this application, it is always 2.
 * @return 64 bit hash value
 */

uint64_t fnv64ahash(void* buf, uint8_t len){
	
	unsigned char *bp = (unsigned char *)buf;	//start of buffer
//  unsigned char *be = bp + len;		// beyond end of buffer 
    unsigned char *be = bp + 2;		// len always equals to 2 in this application 
	uint64_t hval = FNV_64_INIT;
	
	while (bp < be) {
		// xor the bottom with the current octet 
		hval ^= (uint8_t)*bp++;
		
		// multiply by the 32 bit FNV magic prime mod 2^32 
		hval *= FNV_64_PRIME;
    };

    // return the hash value 
    return hval;
	
}

