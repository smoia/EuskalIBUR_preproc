#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )

brain_extract () {
	${SCRIPT_DIR}/brainmask.sh
}

version() {
	local script_file=${1:-''}
	tag=$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; git describe --tags --always)
	echo "M3PI_preproc, $( basename ${script_file} ), version ${tag}"
	echo ""
}

displayhelp() {
	local script_file=$1
	local exit_code=${2:-0}

	if [[ -z ${script_file} ]]
	then
		echo "displayhelp requires the script filename as the first argument"
		exit 3
	fi

	version ${script_file}

	# Extract case block into required and optional
	awk '
		/case[ \t]*"\$1"/ { in_case=1; in_req=1; next }
		in_case {
			if ($0 ~ /^$/ && in_req) { in_req=0; next }  # switch to optional
			if (/esac/) { in_case=0; next }              # end of case block

			# Match only lines that look like a case flag
			if ($0 ~ /^[ \t]*-/) {
				flag = ""; code = ""; desc = ""

				# Extract the flag (first token before ")")
				if (match($0, /^[ \t]*-[^ \t)]*/)) {
					flag = substr($0, RSTART, RLENGTH)
				}

				# Extract code (between ")" and ";;", ignoring comments)
				if (match($0, /\)[ \t]*([^#]*);;/)) {
					tmp = substr($0, RSTART+1, RLENGTH-3)  # skip ")" and ";;"
					gsub(/^[ \t]+|[ \t]+$/, "", tmp)
					code = tmp
				}

				# Extract comment (after "#", if any)
				if (match($0, /#[ \t]*(.*)$/)) {
					tmp = substr($0, RSTART+1)
					gsub(/^[ \t]+|[ \t]+$/, "", tmp)
					desc = tmp
				}

				# If no comment, try to use the variable being set as description
				if (desc == "" && code != "") {
					if (match(code, /^[A-Za-z_][A-Za-z0-9_]*/)) {
						desc = "(sets " substr(code, RSTART, RLENGTH) ")"
					}
				}
				if (desc == "") desc = "(no description)"

				if (in_req) {
					req_flags[++n_req] = flag
					req_desc[n_req] = desc
				} else {
					opt_flags[++n_opt] = flag
					opt_desc[n_opt] = desc
				}
				if (length(flag) > maxlen) maxlen = length(flag)
			}
		}
		END {
			print "Required arguments:"
			for (i=1; i<=n_req; i++) {
				printf "  %-*s  %s\n", maxlen, req_flags[i], req_desc[i]
			}
			if (n_opt > 0) {
				print ""
				print "Optional arguments:"
				for (i=1; i<=n_opt; i++) {
					printf "  %-*s  %s\n", maxlen, opt_flags[i], opt_desc[i]
				}
			}
		}
	' "${script_file}"


	# Only show presets if optional flags exist
	if awk '
		/case[ \t]*"\$1"/ { in_case=1; in_req=1; next }
		in_case {
			if ($0 ~ /^$/ && in_req) { in_req=0; next }
			if (/esac/) exit
			if (!in_req) { found=1; exit }
		}
		END { exit !found }
	' "${script_file}"
	then
		echo
		echo "Default values of optional arguments:"
		awk '
			BEGIN { maxlen = 0 }
			/^# Preparing the default values for variables/ { in_defaults=1; next }
			in_defaults {
				if (/^###/) exit
				if ($0 ~ /^[[:space:]]*$/) next
				split($0, parts, "=")
				varname = parts[1]
				gsub(/[ \t]+$/, "", varname)
				defaults[++n] = $0
				if (length(varname) > maxlen) maxlen = length(varname)
			}
			END {
				for (i=1; i<=n; i++) {
					split(defaults[i], parts, "=")
					varname = parts[1]
					gsub(/[ \t]+$/, "", varname)
					value = substr(defaults[i], length(varname)+2)  # skip = and space
					printf "  %-*s = %s\n", maxlen, varname, value
				}
			}
		' "${script_file}"
	fi

	exit ${exit_code}
}

# Check input
checkreqvar() {
	local reqvar=("$@")
	local vartype

	for var in "${reqvar[@]}"; do
		if [[ -z ${!var+x} ]]; then
			echo "${var} is unset, exiting program" && exit 1
		fi

		vartype=$(declare -p ${var} 2>/dev/null)

		if [[ ${vartype} =~ declare\ \-a\ ([A-Za-z_][A-Za-z0-9_]*)=([\'\"])?(.*)\2 ]]
		then
			echo "${var} is an indexed array ${BASH_REMATCH[3]}"
		elif [[ ${vartype} =~ declare\ \-A\ ([A-Za-z_][A-Za-z0-9_]*)=([\'\"])?(.*)\2 ]]
		then
			echo "${var} is an associative array ${BASH_REMATCH[3]}"
		else
			echo "${var} is set to ${!var}"
		fi
	done
}


checkoptvar() {
	local optvar=("$@")
	local vartype

	for var in "${optvar[@]}"
	do
		vartype=$(declare -p ${var} 2>/dev/null)

		if [[ ${vartype} =~ declare\ \-a\ ([A-Za-z_][A-Za-z0-9_]*)=([\'\"])?(.*)\2 ]]
		then
			echo "${var} is an indexed array ${BASH_REMATCH[3]}"
		elif [[ ${vartype} =~ declare\ \-A\ ([A-Za-z_][A-Za-z0-9_]*)=([\'\"])?(.*)\2 ]]
		then
			echo "${var} is an associative array ${BASH_REMATCH[3]}"
		else
			echo "${var} is set to ${!var}"
		fi
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
				* ) echo "and you shouldn't see this"; exit 2;;
			esac
		fi
		;;
esac
}

replace_and() {
case $1 in
	mkdir) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; mkdir -p "${@:2}" ;;
	touch) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; touch $2 ;;
	* ) echo "This is wrong"; exit 2;;
esac
}

parse_filename_from_json() {
	local bidslabels="task acq ce rec dir run mod echo part chunk recording suffix"
	if [[ -f ${2} ]]
	then
		if [[ $(jq .${1} ${2}) != "null" ]];
		then
			local bidsinfo=''
			local key
			for key in ${bidslabels};
			do
				local value
				value=$(jq -r .${1}.${key} ${2})
				[[ ${value} != "null" ]] && bidsinfo="${bidsinfo}_${key}-${value}"
			done
			echo "${bidsinfo}"
		else
			echo "none"
		fi
	else
		exit 1
	fi
}


# Copyright 2025, Stefano Moia

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
