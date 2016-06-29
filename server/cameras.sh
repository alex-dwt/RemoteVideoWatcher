#!/bin/bash
# This file is part of the RemoteVideoWatcher package.
# (c) Alexander Lukashevich <aleksandr.dwt@gmail.com>
# For the full copyright and license information, please view the LICENSE file that was distributed with this source code.

export LD_LIBRARY_PATH=/camera/streamer

PID_PATH=/camera/streamer/run/
PID_LOCK=/camera/streamer/run/lock

CAMERA_MAX_ID=%_camera_max_id_%

startCamera() {
	local res=$(isCameraRunning $1)	
	local PID=""

	if [ $res == "0" ]; then
		stopAllCameras
		case $1 in
#_list_of_cameras
		esac

		if [ -z $PID ]; then
			echo "Can't start program $1"
			exitProgram 1
		else
			local PID_FILE=$(getCameraPidFile $1)
			echo $PID > $PID_FILE
		fi
 	fi
}

stopCamera() {
	local res=$(isCameraRunning $1)

	if [ $res == "1" ]; then
		local PID_FILE=$(getCameraPidFile $1)
		local PID=$(cat $PID_FILE)
	    kill $PID
		while [ -e /proc/$PID ]
		do
    		sleep 0.1
		done

		res=$(ps axf | grep ${PID} | grep -v grep)

		if [ -n "$res" ]; then
			echo "Can't kill program $1"
			exitProgram 1
		fi

	    rm -f $PID_FILE
	fi
}

stopAllCameras() {
	local i=0
	while [ $i -le $CAMERA_MAX_ID ]; do
	   	stopCamera $i
		i=$(($i+1))
	done
}

isCameraRunning() {
	local PID_FILE=$(getCameraPidFile $1)
     
	if [ -f $PID_FILE ]; then
		echo "1"
	else
		echo "0"
	fi
}

getCameraPidFile() {
	echo ${PID_PATH}${1}.pid
}

exitProgram() {
	rmdir $PID_LOCK
	exit $1
}


while true
do
	if mkdir -p $PID_LOCK > /dev/null 2>&1; then
		break
	fi
	sleep 0.1
done

case $1 in
	
	start)
		if [[ -n "$2"  &&  "10#$2" -ge "0"  &&  "10#$2" -le "$CAMERA_MAX_ID" ]]; then
			startCamera $2
		else 
			echo "camera_id is null or invalid" 
			exitProgram 1
		fi
		;;

	stop)
		if [[ -n "$2"  &&  "10#$2" -ge "0"  &&  "10#$2" -le "$CAMERA_MAX_ID" ]]; then
			stopCamera $2
		else 
			echo "camera_id is null or invalid" 
			exitProgram 1
		fi
		;;

	get-active-camera-id)
		i=0
		while [ $i -le $CAMERA_MAX_ID ]; do
			res=$(isCameraRunning $i)
			if [ $res == "1" ]; then
			   	echo $i
				exitProgram 0
			fi
			i=$(($i+1))
		done
		echo "-1" 
		;;

	stop-all)
		stopAllCameras
		;;
	*)
		echo "Wrong command"
		exitProgram 1
		;;
esac

exitProgram 0
