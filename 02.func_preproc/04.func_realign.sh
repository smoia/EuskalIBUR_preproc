#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
computeoutliers=no
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
		-fmat)		fmat=$2;shift;;
		-mask)		mask=$2;shift;;
		-fdir)		fdir=$2;shift;;
		-mref)		mref=$2;shift;;

		-computeoutliers)		computeoutliers=yes;;
		-tmp)					tmp=$2;shift;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fmat mask fdir mref
checkoptvar computeoutliers tmp

### Remove nifti suffix
for var in func_in mask  mref
do
	eval "${var}=${!var%.nii*}"
done

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
func=$( basename ${func_in%_*} )

nTR=$(fslval ${func_in} dim4)
TR=$(fslval ${func_in} pixdim4)
let nTR--

## 01. Motion Realignment

# 01.1. Apply McFlirt
echo "Applying McFlirt in ${func}"

replace_and mkdir ${tmp}/${func}_split
replace_and mkdir ${tmp}/${func}_merge
fslsplit ${func_in} ${tmp}/${func}_split/vol_ -t

for i in $( seq -f %04g 0 ${nTR} )
do
	echo "Flirting volume ${i} of ${nTR} in ${func}"
	flirt -in ${tmp}/${func}_split/vol_${i} -ref ${mref} -applyxfm \
	-init ../reg/$( basename ${fmat} )_mcf.mat/MAT_${i} -out ${tmp}/${func}_merge/vol_${i}
done

echo "Merging ${func}"
fslmerge -tr ${tmp}/${func}_mcf ${tmp}/${func}_merge/vol_* ${TR}

# 01.2. Apply mask
echo "BETting ${func}"
fslmaths ${tmp}/${func}_mcf -mas ${mask} ${tmp}/${func}_bet

if [[ "${computeoutliers}" == "yes" ]]
then
	echo "Computing DVARS and FD for ${func}"
	# 01.3. Compute various metrics
	fsl_motion_outliers -i ${tmp}/${func}_mcf -o ${tmp}/${func}_mcf_dvars_confounds \
						-s ${func}_dvars_post.par -p ${func}_dvars_post --dvars --nomoco
	fsl_motion_outliers -i ${tmp}/${func}_cr -o ${tmp}/${func}_mcf_dvars_confounds \
						-s ${func}_dvars_pre.par -p ${func}_dvars_pre --dvars --nomoco
	fsl_motion_outliers -i ${tmp}/${func}_cr -o ${tmp}/${func}_mcf_fd_confounds \
						-s ${func}_fd.par -p ${func}_fd --fd
fi

cd ${cwd}