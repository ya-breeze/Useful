#!/bin/bash
# Log grabber
# Created by Ilya Korolev <ilya.korolev@teligent.ru>
#
DEBUG="1"

VERSION="0.0.4"
DATAROOT="/tmp/grabber"
SERVERPATH="/root/.grabber.sh"
MODULEPATH="$SERVERPATH.modules"

# timeout in seconds for keep-alive from client
CACHETTL="60"
# timeout in seconds to send keep-alive
SEND_KEEPALIVE="30"

function debug() {
	if [[ "x$DEBUG" == "x1" ]]; then
		echo $*
	fi
}

function log() {
	echo "$*"
}

# Waiting for CTRL+C
STOPFILE="/tmp/stopfile.$RANDOM"
sigint() {
    echo "SIGINT is received"
    touch $STOPFILE
}
rm -f $STOPFILE

# Ensures, that user has valid ssh connection. If not - trying to set it up
function checkSsh() {
	local NICKNAME=$1
	local HOST=$2
	local PORT=$3

	ssh -o BatchMode=yes -p$PORT $HOST /bin/true >/dev/null 2>&1
	RESULT=$?
	if [[ $RESULT != "0" ]]; then
		log "Need to setup password-less connection to $NICKNAME"
		ssh-copy-id "-p$PORT $HOST"
		ssh -o BatchMode=yes -p$PORT $HOST /bin/true >/dev/null 2>&1
		RESULT=$?
		if [[ $RESULT != "0" ]]; then
			log "Unable automatically setup connection to $NICKNAME, try do it manually"
			exit 1
		fi
	fi
}

# Sending command to server
function sendCommand() {
	local NICKNAME=$1
	local HOST=$2
	local PORT=$3
	local COMMAND=$4

	ssh -x -o BatchMode=yes -p$PORT $HOST $COMMAND 2>&1
}

# Check existance of current version of this script and update it if necessery
function checkCurrentVersion() {
	local NICKNAME=$1
	local HOST=$2
	local PORT=$3

	REMOTE_VERSION=$(sendCommand $NICKNAME $HOST $PORT "$SERVERPATH version")
	RESULT=$?
	if [[ $RESULT != "0" || $REMOTE_VERSION != $VERSION ]]; then
		debug "Updating grabber on $NICKNAME"
		scp -P$PORT $0 $HOST:$SERVERPATH>/dev/null
	fi
}

# Check existance of current version of modules and update it if necessery
function checkModules() {
	local NICKNAME=$1
	local HOST=$2
	local PORT=$3
	local MODULES=$4

	sendCommand $NICKNAME $HOST $PORT "$SERVERPATH check_modules $MODULES"
	RESULT=$?
	if [[ $RESULT != "0" ]]; then
		debug "Updating modules on $NICKNAME"
		scp -P$PORT modules/* $HOST:$MODULEPATH>/dev/null
	fi
}

################ Server side ################

function syslog() {
	logger -t GRABBER $*
}

function handle_daemon() {
	local MODE=$1
	local ID=$2
	local MODULES=$3
	local NICKNAME=$4

	DATADIR="$DATAROOT-$ID"
	cd $DATADIR
	export DATADIR=$DATADIR
	export NICKNAME=$NICKNAME

	syslog "Starting for session $ID and modules $MODULES"
	echo $$ > daemon.pid

	# Start modules
	for MODULE in `echo $MODULES|sed 's/,/ /g'`; do
		if test -f $MODULEPATH/$MODULE; then
			PID=`$MODULEPATH/$MODULE start`
			echo $PID > $DATADIR/$MODULE.module.pid
		fi
	done

	# Waiting for interrupt
	syslog "Waiting for interrupt - '$ID'"
	while ! test -f stopreason; do
		# Is user online?
		# check timestamp of 'update' file - it should be touched at least minute ago
		if [ -f $DATADIR/update ]; then
			TIMECACHE=`stat -c"%Z" $DATADIR/update`
		else
			TIMECACHE=0
		fi
		TIMENOW=`date '+%s'`
		# syslog ">>> $TIMENOW - $TIMECACHE = $(($TIMENOW - $TIMECACHE)) > $CACHETTL"
		if [ "$(($TIMENOW - $TIMECACHE))" -gt "$CACHETTL" ]; then
			# Stop current grabbing
			syslog "There were no keep-alive pings from client - $ID"
		    echo stop > stopreason
		fi


		sleep 1
	done

	# Stopfile detected
	syslog "Stopfile founded - stop grabbing $ID"
	for MODULE in `ls $DATADIR/*.module.pid`; do
		syslog "Stopping module $MODULE"
		NAME=`basename $MODULE .module.pid`
		PID=`cat $MODULE`
		$MODULEPATH/$NAME `cat stopreason` $PID
		wait $PID
		rm -f $MODULE
	done

	syslog "Daemon '$ID' is finished"

	rm -f daemon.pid stopreason
}

check_modules() {
	local MODULES=$1

	mkdir -p $MODULEPATH

	# Check availability of modules
	for MODULE in `echo $MODULES|sed 's/,/ /g'`; do
		if test ! -f $MODULEPATH/$MODULE; then
			syslog "Module '$MODULE' is absent"
			exit 1
		fi
	done
	syslog "All modules are present"
}

function start_server() {
	local MODE=$1
	local ID=$2
	local MODULES=$3
	local NICKNAME=$4

	syslog "Perform on '$NICKNAME' server '$MODE' with id '$ID' and modules '$MODULES'"

	DATADIR="$DATAROOT-$ID"

	case $MODE in
		start )
			# Start daemon itself
			rm -rf $DATADIR
			mkdir -p $DATADIR
			cd $DATADIR
			touch update
			nohup $0 daemon $MODE $ID $MODULES $NICKNAME 0<&- &>/dev/null &
			;;
		stop )
			rm -f $DATADIR/update
			if test -f $DATADIR/daemon.pid; then
				cd $DATADIR
				echo stop > stopreason
				while test -f $DATADIR/daemon.pid; do
					sleep 1
				done	
			fi
		;;
		update )
			touch $DATADIR/update
		;;
		cancel )
			syslog Need cancel grabbing $ID
			rm -f $DATADIR/update
			cd /tmp
			if test -f $DATADIR/daemon.pid; then
				cd $DATADIR
				echo cancel > stopreason
				while test -f $DATADIR/daemon.pid; do
					sleep 1
				done	
			fi
			rm -rf $DATADIR
			true
		;;
	esac
}

################ Client side ################

function get_remote_files() {
	local SERVERS=$1
	local SESSION=$2

	for SERVER in $SERVERS; do
		NICKNAME=`echo $SERVER|cut -d\; -f1`
		HOSTPORT=`echo $SERVER|cut -d\; -f2`
		HOST=`echo $HOSTPORT|cut -d: -f1`
		PORT=`echo $HOSTPORT|cut -d: -f2`
		MODULES=`echo $SERVER|cut -d\; -f3`

		debug "$NICKNAME - $HOST:$PORT - $MODULES"
		sendCommand $NICKNAME $HOST $PORT "test -d $DATAROOT-$SESSION"
		RESULT=$?
		if [[ $RESULT == "0" ]]; then
			scp -C -q -P $PORT $HOST:$DATAROOT-$SESSION/* $DATAROOT-$SESSION
			sendCommand $NICKNAME $HOST $PORT "rm -rf $DATAROOT-$SESSION"
		fi
	done
}

function remote_servers() {
	local SERVERS=$1
	local MODE=$2
	local SESSION=$3

	for SERVER in $SERVERS; do
		NICKNAME=`echo $SERVER|cut -d\; -f1`
		HOSTPORT=`echo $SERVER|cut -d\; -f2`
		HOST=`echo $HOSTPORT|cut -d: -f1`
		PORT=`echo $HOSTPORT|cut -d: -f2`
		MODULES=`echo $SERVER|cut -d\; -f3`

		debug "$NICKNAME - $HOST:$PORT - $MODULES"
		start_remote_server $NICKNAME $HOST $PORT $MODE $SESSION $MODULES
	done
}

function start_remote_server() {
	local NICKNAME=$1
	local HOST=$2
	local PORT=$3
	local MODE=$4
	local SESSION=$5
	local MODULES=$6

	sendCommand $NICKNAME $HOST $PORT "$SERVERPATH server $MODE $SESSION $MODULES $NICKNAME"
	RESULT=$?
	if [[ $RESULT != "0" ]]; then
		log "Unable start server on '$NICKNAME'"
	fi
}

function start_client() {
	if [[ "x$1" == "x" ]]; then
		log "Usage: $0 <config file> <start | stop | cancel> [SESSION]"
		log "       $0 <config file>                  - perform all steps at once"
		log "       $0 <config file> start            - start grabbing"
		log "       $0 <config file> stop <SESSION>   - stop grabbing and download all files. Useful after network error"
		log "       $0 <config file> cancel <SESSION> - cancel grabbing. Useful after network error"
		exit 1
	fi
	debug "Starting as a client side with $1"

	# include config file
	. $1

	MODE=$2
	SESSION=$3

	# check ssh connection
	log "Checking connection..."
	for SERVER in $SERVERS; do
		NICKNAME=`echo $SERVER|cut -d\; -f1`
		HOSTPORT=`echo $SERVER|cut -d\; -f2`
		HOST=`echo $HOSTPORT|cut -d: -f1`
		PORT=`echo $HOSTPORT|cut -d: -f2`
		MODULES=`echo $SERVER|cut -d\; -f3`

		debug "$NICKNAME - $HOST:$PORT - $MODULES"
		checkSsh $NICKNAME $HOST $PORT
		checkCurrentVersion $NICKNAME $HOST $PORT
		checkModules $NICKNAME $HOST $PORT $MODULES
	done

	# Perform main logic
	case $MODE in
		start )
			# Generate new session ID
			SESSION=`hostname`
			SESSION="$SESSION-$RANDOM"
			log "Start session $SESSION"

			# prepare directory for dump
			rm -rf $DATAROOT-$SESSION
			mkdir -p $DATAROOT-$SESSION

			# start grabbing
			log "Start grabbing..."
			remote_servers "$SERVERS" $MODE $SESSION
		;;
		stop )
			# stop will be called only if grabber session was interrupted
			if [[ "x$SESSION" == "x" ]]; then
				log "Unable stop unknown session"
				exit 1
			fi

			log "Stopping session $SESSION"
			remote_servers "$SERVERS" $MODE $SESSION
			get_remote_files "$SERVERS" $SESSION
			log "Done. You can find files in '$DATAROOT-$SESSION'"
		;;
		cancel )
			if [[ "x$SESSION" == "x" ]]; then
				log "Unable cancel unknown session"
				exit 1
			fi

			log "Cancel session $SESSION"
			remote_servers "$SERVERS" $MODE $SESSION
		;;
		continue )
			if [[ "x$SESSION" == "x" ]]; then
				log "Unable continue unknown session"
				exit 1
			fi

			log "Continue grabbing for session $SESSION"
			trap sigint INT

			log "Press CTRL+C to stop grabber"
			while test ! -f $STOPFILE; do
				debug "Sending keep-alive"
				remote_servers "$SERVERS" update $SESSION
				sleep $SEND_KEEPALIVE
			done

			# Fetching
			log "Grabbing..."
			remote_servers "$SERVERS" stop $SESSION
			get_remote_files "$SERVERS" $SESSION
			log "Done. You can find files in '$DATAROOT-$SESSION'"
			rm -f $STOPFILE
		;;
		* )
			# Generate new session ID
			SESSION=`hostname`
			SESSION="$SESSION-$RANDOM"
			log "Start session $SESSION"

			# prepare directory for dump
			rm -rf $DATAROOT-$SESSION
			mkdir -p $DATAROOT-$SESSION

			trap sigint INT

			remote_servers "$SERVERS" start $SESSION
			log "Press CTRL+C to stop grabber"
			while test ! -f $STOPFILE; do
				debug "Sending keep-alive"
				remote_servers "$SERVERS" update $SESSION
				sleep $SEND_KEEPALIVE
			done

			# Fetching
			log "Grabbing..."
			remote_servers "$SERVERS" stop $SESSION
			get_remote_files "$SERVERS" $SESSION
			log "Done. You can find files in '$DATAROOT-$SESSION'"
			rm -f $STOPFILE
		;;
	esac

}

################  MAIN  #################
case $1 in
	version )
		echo $VERSION
		exit 0
		;;
	server )
		shift
		start_server $*
		;;
	check_modules )
		shift
		check_modules $*
		;;
	daemon )
		shift
		handle_daemon $*
		;;
	* )
		start_client $*
		;;
esac
