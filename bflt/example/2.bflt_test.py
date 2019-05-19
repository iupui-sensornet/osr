import BloomFilter

bflt_len = 3*8
for i in range(1, 1000):
	b = BloomFilter.getBflt(i, bflt_len)
	print str(i) + '\t' + str(b)
