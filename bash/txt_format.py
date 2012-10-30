#!/usr/bin/python

import codecs

filename='/tmp/1.txt'
f = codecs.open(filename, encoding='utf-8')
out = codecs.open(filename+'.output', encoding='utf-8', mode='w+')
block=''
firstline=True
for line in f:
    print len(line)
    if len(line)>66:
	line=line[0:66]
    line=line.rstrip()
    print len(line), line[0:1]==' '

    print len(line), line[0:1]==' '
    if not firstline and (len(line)<=1 or line[0:1]==' ' or line[0:1]=='\t'):
	out.write(block)
	out.write('\n')
	block=line
    else:
	if len(block)>0:
	    block+=' '
	block+=line

    firstline=False

out.write(block)
out.write('\n')
