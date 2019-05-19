



interface BloomFilter {
	
	/**
	 * Return a bloom filter given an integer.
	 * id: the node id
	 * *bflt: the pointer to the bflt array
	 * bflt_len: the number of bytes in the bloom filter
	 * @return bloom filter 
	 */
	command void getBflt(uint16_t id, nx_uint8_t* bflt, uint8_t bflt_len);

}
