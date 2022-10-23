#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir TEs"
echo "Optional:"
echo "tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

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
		-fdir)		fdir=$2;shift;;
		-TEs)		TEs="$2";shift;;

		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir TEs
checkoptvar tmp

### Remove nifti suffix
func_in=${func_in%.nii*}

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
esfx=$( basename ${func_in#*_echo-?} )
eprx=$( basename ${func_in%_echo-*}_echo- )
func=$( basename ${func_in%_echo-*}_concat${esfx} )
func_optcom=$( basename ${func_in%_echo-*}_optcom${esfx} )

## 01. MEICA
# 01.1. concat in space

if [[ ! -e ${tmp}/${func}.nii.gz ]];
then
	echo "Merging ${func} for MEICA"
	fslmerge -z ${tmp}/${func} $( ls ${tmp}/${eprx}* | grep ${esfx}.nii.gz )
else
	echo "Merged ${func} found!"
fi

if [[ ! -e ${tmp}/${func_optcom} ]]
then
	echo "Running t2smap"
	cd ${tmp} || exit
	t2smap -d ${tmp}/${func}.nii.gz -e ${TEs}

	echo "Housekeeping"
	fslmaths TED.${func}/ts_OC.nii.gz ${tmp}/${func_optcom} -odt float
	cd ${fdir} || exit
fi

# 01.3. Compute outlier fraction if there's more than one TR
nTR=$(fslval ${tmp}/${func_optcom} dim4)

if [[ "${nTR}" -gt "1" ]]
then
	echo "Computing outlier fraction in ${func_optcom}"
	fslmaths ${tmp}/${func_optcom} -Tmean ${tmp}/${func_optcom}_avg
	bet ${tmp}/${func_optcom}_avg ${tmp}/${func_optcom}_brain -R -f 0.5 -g 0 -n -m
	3dToutcount -mask ${tmp}/${func_optcom}_brain_mask.nii.gz -fraction -polort 5 -legendre ${tmp}/${func_optcom}.nii.gz > ${func_optcom%_bet}_outcount.1D
	imrm ${tmp}/${func_optcom}_avg ${tmp}/${func_optcom}_brain ${tmp}/${func_optcom}_brain_mask
fi

cd ${cwd}
