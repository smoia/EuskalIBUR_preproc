#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-func_in)	func_in=$2;shift;;

		-tmp)		tmp=$2;shift;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar func_in
checkoptvar tmp

### Remove nifti suffix
func_in=${func_in%.nii*}

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

#Read and process input
func=$( basename ${func_in%_*} )

echo "Computing SPC of ${func} ( [X-avg(X)]/avg(X) )"

fslmaths ${func_in} -Tmean ${tmp}/${func}_mean
fslmaths ${func_in} -sub ${tmp}/${func}_mean -div ${tmp}/${func}_mean ${tmp}/${func}_SPC

cd ${cwd}