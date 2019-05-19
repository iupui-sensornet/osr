'''
check the conflict in the bflt for each node id

'''

inf = open("20160415-bflt_test1.txt", "r")

outf = open("20160415-bflt_test1_confilct_check.txt", "w")

#key = bflt, value = [id1, id2, ...]
bflt = {}

counter = 0

lines = inf.readlines()
line_count = 0
for line in lines:
	s = line.split()
	if len(s) <= 0:
		continue
		
	line_count += 1
	cur_bflt = s[len(s)-1]
	cur_id = s[4]
	if not bflt.has_key(cur_bflt):
		bflt[cur_bflt] = []
	
	bflt[cur_bflt].append(cur_id)

for key in bflt:
	if len(bflt[key]) == 1:
		# the number of unique keys
		counter += 1	
	else:
		newline = key + ": " + str(bflt[key]) + '\n'
		outf.writelines(newline)

outf.writelines("number of unique keys is: " + str(counter)+ '\n')
outf.writelines("conflict ratio is: " + str(1-counter*1.0/line_count) + '\n')

inf.close()
outf.close()
