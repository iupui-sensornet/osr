   
import sys
import time

from TOSSIM import *

t = Tossim([])
m = t.mac()
r = t.radio()


N = 1

t.addChannel("BloomFilterC", sys.stdout);
t.addChannel("TestBfltC", sys.stdout);
t.addChannel("TestMatch", sys.stdout);

for i in range (1, N+1):
	t.getNode(i).bootAtTime((31 + t.ticksPerSecond() / 10) * i + 1);


for i in range(0, 1000):

  t.runNextEvent();


