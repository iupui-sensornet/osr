/*
 * Test application of the bloom filter
 * 
 * @author 	Xiaoyang Zhong
 * @date	2016-4-2
 */
 
 configuration TestBfltAppC {}
 implementation{
 	components TestBfltC as App;
 	components MainC;
 	components BloomFilterC;
 	components new TimerMilliC();
 	
 	App.Boot -> MainC;
 	App.BloomFilter -> BloomFilterC;
 	App.Timer -> TimerMilliC;
 }
