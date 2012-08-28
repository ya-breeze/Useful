#!/bin/bash

# This is a script for monitoring Mysql status
# Script should be executed as:
#    watch -d -n1 ./get_cps.sh 192.168.64.24 3306 - it will monitor Mysql every second and write operations per second

HOST=$1
PORT=$2
PARAMS="Com_delete|Com_insert|Com_select|Com_update|Com_replace|Qcache_hits"
PREFIX="/tmp/mysql_status_per_second.$HOST:$PORT"

if [ "x$1" == "x" ];then
    echo "Usage: $0 <host> <port> | $0 clean"
    exit -1
elif [ "x$1" == "xclean" ];then
    rm -f $PREFIX.*
    exit 0
fi

VALUES=`mysqladmin -uteligent -pteligent -h$HOST -P$PORT extended-status | grep -E $PARAMS| awk '{print $2":"$4}'`

echo "Mysql on $HOST:$PORT"

for I in $VALUES; do
    NAME=`echo $I | cut -f1 -d:`
    VALUE=`echo $I | cut -f2 -d:`
    LAST=`cat $PREFIX.$NAME 2>/dev/null || echo 0`
    DIFF=`expr $VALUE - $LAST`
    echo "$NAME - $DIFF"
    echo $VALUE > $PREFIX.$NAME
done

echo
echo
