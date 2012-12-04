#!/usr/bin/python

# Example to parse key-value pairs like this:
# ISRT TABLE="AID" NAME="" EXEC="" SHELL="" SNMP="1" KEY="2" PROBCAUSE="255" TEXT="..."
# Based on http://stackoverflow.com/questions/1644362/best-way-to-parse-a-line-in-python-to-a-dictionary

import re
import sys

if len(sys.argv) < 2:
    sys.exit('Usage: %s filename' % sys.argv[0])

FILE=sys.argv[1]
r=re.compile('([^ =]+) *= *("[^"]*"|[^ ]*)')

with open(FILE) as myfile:
	for line in myfile:
		d={}
		for k, v in r.findall(line):
			d[k]= v[1:-1]
		print d['KEY'], '\t', d['TEXT']
  