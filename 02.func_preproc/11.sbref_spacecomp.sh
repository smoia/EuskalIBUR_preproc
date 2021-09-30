#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $(dirname "$0")/../utils.sh

displayhelp() {
echo "Required:"
echo "sbrf_in fdir"
echo "Optional:"
echo "anat adir"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=none
adir=none

# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sbrf_in)	sbrf_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)		anat=$2;shift;;
		-adir)		adir=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
checkreqvar sbrf_in fdir
checkoptvar anat adir

### Remove nifti suffix
for var in sbrf_in anat
do
eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
sbrf=$( basename ${sbrf_in%_*} )
sbrfsfx=${sbrf#*ses-*_}

## 01. BET
echo "BETting ${sbrf}"
bet ${sbrf_in} ${sbrf}_brain -R -f 0.5 -g 0 -n -m

## 02. Anat Coreg
if [[ "${anat}" != "none" ]]
then
	if [[ "${adir}" != "none" ]]; then anat=${adir}/${anat}; fi
	if_missing_do stop ${anat}_brain
	echo "Coregistering ${sbrf} to ${anat}"
	flirt -in ${anat}_brain -ref ${sbrf}_brain -out ${anat}2${sbrfsfx} -omat ../reg/${anat}2${sbrfsfx}_fsl.mat \
	-searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ${sbrf}_brain -src ${anat}_brain \
	../reg/${anat}2${sbrfsfx}_fsl.mat -fsl2ras -oitk ../reg/${anat}2${sbrfsfx}0GenericAffine.mat
fi

cd ${cwd}