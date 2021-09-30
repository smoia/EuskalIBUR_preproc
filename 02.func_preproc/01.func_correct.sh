#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $(dirname "$0")/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "voldiscard despike slicetimeinterp tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
voldiscard=0
despike=no
slicetimeinterp=no
tmp=.

# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-func_in)	func_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-voldiscard)		voldiscard=$2;shift;;
		-despike)			despike=yes;;
		-slicetimeinterp)	slicetimeinterp=yes;;
		-tmp)				tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
checkreqvar func fdir
checkoptvar voldiscard despike slicetimeinterp tmp

### Remove nifti suffix
func_in=${func_in%.nii*}

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
func=$( basename ${func_in%_*} )
nTR=$(fslval ${func_in} dim4)

## 01. Corrections
# 01.1. Discard first volumes if there's more than one TR

funcsource=${func_in}
if [[ "${nTR}" -gt "1" && "${voldiscard}" -gt "0" ]]
then
	echo "Discarding first ${voldiscard} volumes"
	# The next line was added due to fslroi starting from 0, however it does not.
	# let voldiscard--
	fslroi ${funcsource} ${tmp}/${func}_dsd.nii.gz ${voldiscard} -1
	funcsource=${tmp}/${func}_dsd
fi
# 01.2. Deoblique & resample
echo "Deoblique and RPI orient ${func}"
3drefit -deoblique ${funcsource}.nii.gz
3dresample -orient RPI -inset ${funcsource}.nii.gz -prefix ${tmp}/${func}_RPI.nii.gz -overwrite
# set name of source for 3dNwarpApply
funcsource=${tmp}/${func}_RPI
# 01.3. Compute outlier fraction if there's more than one TR
if [[ "${nTR}" -gt "1" ]]
then
	echo "Computing outlier fraction in ${func}"
	fslmaths ${funcsource} -Tmean ${tmp}/${func}_avg
	bet ${tmp}/${func}_avg ${tmp}/${func}_brain -R -f 0.5 -g 0 -n -m
	3dToutcount -mask ${tmp}/${func}_brain_mask.nii.gz -fraction -polort 5 -legendre ${funcsource}.nii.gz > ${func}_outcount.1D
fi

# 01.4. Despike if asked
if [[ "${despike}" == "yes" ]]
then
	echo "Despike ${func}"
	3dDespike -prefix ${tmp}/${func}_dsk.nii.gz ${funcsource}.nii.gz
	funcsource=${tmp}/${func}_dsk
fi

## 02. Slice Interpolation if asked
if [[ "${slicetimeinterp}" == "yes" ]]
then
	echo "Slice Interpolation of ${func}"
	3dTshift -Fourier -prefix ${tmp}/${func}_si.nii.gz \
	-tpattern ${slicetimeinterp} -overwrite \
	${funcsource}.nii.gz
	funcsource=${tmp}/${func}_si
fi

## 03. Change name to script output
immv ${funcsource} ${tmp}/${func}_cr

cd ${cwd}