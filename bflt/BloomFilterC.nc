/*
 * Given a node id, return the bloom filter with the corresponding bit set.
 * 
 * @author 	Xiaoyang Zhong
 * @date	2016-04-02
 */

#include "BloomFilter.h"
#include "fnv.h"

configuration BloomFilterC{
	provides interface BloomFilter;
} 
implementation {
	components BloomFilterP;
	BloomFilter = BloomFilterP;
}
