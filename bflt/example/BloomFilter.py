
'''
This bflt can generate the same bflt as the tinyos code

Used to verify the correctness of TOSSIM simulation

'''
FNV_32_PRIME = 0x01000193
FNV_32_INIT = 0x811c9dc5

FNV_64_PRIME = 0x100000001b3
FNV_64_INIT = 0x14650FB0739D0383




L = 128		# the number of bits in the Bloom Filter
H = 3		# the number of hash values to set the bits in Bloom Filter
MASK = 0x3F	# the mask used to get generate hash value between 0 ~ L-1
SHIFT_BITS = 6	# the number of bits to shift based on the MASK

SHIFT_1 = 1


'''
/*
	 * Implementation of Thomas Wang's integer hash function
	 * https:#gist.github.com/badboy/6267743
	 * https:#naml.us/blog/tag/thomas-wang
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *	   the node id.
	 *
	 * @return 64 bit hash value
	 */
'''
def twhash64(buf):
	key = buf
	key = (~key) + (key << 21) # key = (key << 21) - key - 1
	key = key ^ (key >> 24)
	key = (key + (key << 3)) + (key << 8) # key * 265
	key = key ^ (key >> 14)
	key = (key + (key << 2)) + (key << 4) # key * 21
	key = key ^ (key >> 28)
	key = key + (key << 31)
	return key

'''
	/*
	 * Implementation of Bob Jenkins's integer hash function
	 * http:#burtleburtle.net/bob/hash/integer.html
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *	   the node id.
	 *
	 * @return 32 bit hash value
	 */
'''
def bjhash32(buf):
	a = buf
	a -= (a<<6) 
	a = a & 0xffffffff
	a ^= (a>>17)
	a = a & 0xffffffff
	a -= (a<<9)
	a = a & 0xffffffff
	a ^= (a<<4)
	a = a & 0xffffffff
	a -= (a<<3)
	a = a & 0xffffffff
	a ^= (a<<10)
	a = a & 0xffffffff
	a ^= (a>>15)
	a = a & 0xffffffff
	return a

'''
	/*
	 * Implementation of 64-bit FNV1-a hash
	 
	 * @param buf: The seed to generate the hash value. In this application, it is 
	 *	   the node id.
	 *	  len: the size of the buffer. In this application, it is always 2.
	 * @return 64 bit hash value
	 */
'''
def fnv64ahash(buf, buf_size):

#	bp = str(buf)	#start of buffer
#	be = bp + len	# beyond end of buffer 
	bp = buf
	hval = FNV_64_INIT
	
	for i in range(0, buf_size):
	
		hval ^= ((bp >> i*8)&0xff)
		hval *= FNV_64_PRIME
		
#	while (bp < be) {
	# xor the bottom with the current octet 
#	hval ^= (uint8_t)*bp++
	
	# multiply by the 32 bit FNV magic prime mod 2^32 
#	hval *= FNV_64_PRIME
#	}

	return hval
	

def fnv32ahash(buf, buf_size):
	
	bp = buf;	

	hval_fnv = FNV_32_INIT;


	for i in range(0, buf_size):
		hval_fnv ^= ((bp >> i*8)&0xff)
		hval_fnv *= FNV_32_PRIME
	return hval_fnv

	

'''
	/*
	 * Given a node id, return the bloom filter with the bits set
	 * 
	 * @param 	id: the AM address, 16-bit integer
	 * @return	bflt: the bflt with the bits set
	 */
'''
def getBflt(nodeid, bflt_len):
	# bflt_len: the bflt length in bits
	# 
	bFlt = 0
	ret = range(H)
	actual_ret = range(H)
	hval = range(H)
	seed = nodeid*10000 + (0xfffff+1001)

#	hval[0] = fnv64ahash(seed, 4)	# 2 is the number of bytes in id
	hval[0] = fnv32ahash(seed, 4)
	hval[1] = twhash64(seed)	# 2 is the number of bytes in id
	hval[2] = bjhash32(seed)
	
	count = 0 
	i = 0
	t = 1
	tmp = 0

	for i in range(H):
		tmp = hval[i] % L
		ret[i] = tmp
		
		actual_bit = tmp % bflt_len
		bFlt = bFlt | (t << actual_bit)
		actual_ret[i] = actual_bit
		
#		
#	tmp = hval1 % L
##	bFlt = bFlt | (t << tmp)
#	ret[0] = tmp
#	
#	actual_bit = tmp % bflt_len
#	bFlt = bFlt | (t << actual_bit)
#	actual_ret[0] = actual_bit
#	
#	#	dbg("BloomFilterC", "BloomFilterC: the bit to be set is: %d, bflt is: %llu\n", tmp, bFlt)
#	
#	tmp = hval2 % L
##	bFlt = bFlt | (t << tmp)
#	ret[1] = tmp
#	actual_bit = tmp % bflt_len
#	bFlt = bFlt | (t << actual_bit)
#	actual_ret[1] = actual_bit
#	#	dbg("BloomFilterC", "BloomFilterC: the bit to be set is: %d, bflt is: %llu\n", tmp, bFlt)
#	
#	tmp = hval3 % L
##	bFlt = bFlt | (t << tmp)
#	ret[2] = tmp
#	#	dbg("BloomFilterC", "BloomFilterC: the bit to be set is: %d, bflt is: %llu\n", tmp, bFlt)
#	actual_bit = tmp % bflt_len
#	bFlt = bFlt | (t << actual_bit)
#	actual_ret[2] = actual_bit
	
	print "\nthe original bit to be set is:\t%d\t%d\t%d" % (ret[0], ret[1], ret[2])
	print "\t\t the actual bit to be set is: \t%d\t%d\t%d" % (actual_ret[0], actual_ret[1], actual_ret[2])
	return bFlt
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	

