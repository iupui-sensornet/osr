#ifndef FNV_H
#define FNV_H

uint32_t fnv32hash(void* buf, uint8_t len);
uint32_t fnv32ahash(void* buf, uint8_t len);

uint64_t fnv64hash(void* buf, uint8_t len);
uint64_t fnv64ahash(void* buf, uint8_t len);

#endif
