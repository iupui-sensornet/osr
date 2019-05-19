#ifndef BLOOM_FILTER_H
#define BLOOM_FILTER_H


#define FNV_32_PRIME 0x01000193
#define FNV_32_INIT 0x811c9dc5

#define FNV_64_PRIME 0x100000001b3
#define FNV_64_INIT 0x14650FB0739D0383

#define ROT32(x, y) ((x << y) | (x >> (32 - y))) // for murmur hash

#ifndef BFLT_MAXL
#define BFLT_MAXL 128
#endif 

#ifndef BFLT_H
#define BFLT_H 3
#endif 

#endif
