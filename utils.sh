#!/usr/bin/env bash

version() {
	echo "Version 0.0.0"
}

# Check input
checkreqvar() {
	reqvar=( "$@" )

	for var in "${reqvar[@]}"
	do
		if [[ -z ${!var+x} ]]
		then
			echo "${var} is unset, exiting program" && exit 1
		else
			echo "${var} is set to ${!var}"
		fi
	done
}

checkoptvar() {
	optvar=( "$@" )

	for var in "${optvar[@]}"
	do
		echo "${var} is set to ${!var}"
	done
}

removeniisfx() {
	echo ${1%.nii*}
}

if_missing_do() {
case $1 in
	mkdir )
		if [ ! -d $2 ]
		then
			echo "Create folder(s)" "${@:2}"
			mkdir -p "${@:2}"
		fi
		;;
	stop )
		if [ ! -e $2 ]
		then
			echo "$2 not found"
			exit 1
		fi
		;;
	* )
		if [ ! -e $3 ]
		then
			printf "%s is missing, " "$3"
			case $1 in
				copy ) echo "copying $2";		cp $2 $3 ;;
				move ) echo "moving $2";		mv $2 $3 ;;
				mask ) echo "binarising $2";	fslmaths $2 -bin $3 ;;
				* ) echo "and you shouldn't see this"; exit ;;
			esac
		fi
		;;
esac
}

replace_and() {
case $1 in
	mkdir) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; mkdir -p "${@:2}" ;;
	touch) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; touch $2 ;;
	* ) echo "This is wrong"; exit ;;
esac
}

parse_json_name() {
	bidslabels="task acq ce rec dir run mod echo part chunk recording"
	if [[ -f ${2} ]]
	then
		echo "Looking for '${1}' bids labels in json ${2}"
		if [[ $(jq .${1} ${2}) != "null" ]];
		then
			bidsinfo=''
			for key in ${bidslabels};
			do
				value=$(jq -r .${1}.${key} ${2})
				[[ ${value} != "null" ]] && bidsinfo="${bidsinfo}_${key}-${value}"
			done
			echo "'${1}' bids labels are '${bidsinfo}'"
			# exit
		else
			echo "'${1}' bids labels not found in json ${2}"
			# exit 1
		fi
	else
		echo "Could not find '${2}'"
	fi
}

