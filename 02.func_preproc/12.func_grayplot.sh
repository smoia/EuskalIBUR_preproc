#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $(dirname "$0")/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "anat adir mref aseg pol tmp"
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
mref=none
aseg=none
pol=4
tmp=.

# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-func_in)	func_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)		anat=$2;shift;;
		-adir)		adir=$2;shift;;
		-mref)		mref=$2;shift;;
		-aseg)		aseg=$2;shift;;
		-pol)		pol=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
checkreqvar func_in fdir
checkoptvar anat adir mref aseg pol tmp

### Remove nifti suffix
for var in func_in anat mref aseg
do
eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
func=$( basename ${func_in%_*} )
mref_in=${mref}

asegsfx=$( basename ${aseg} )
asegsfx=${aseg#*ses-*_}
mrefsfx=$( basename ${mref} )
mrefsfx=${mref#*ses-*_}

if [[ "${mref}" == "none" ]]; then mref=${func}; mref_in=${func_in}; fi
if [[ ! -e "${mref}_brain_mask" ]]
then
	echo "BETting reference ${mref}"
	bet ${mref_in} ${mref}_brain -R -f 0.5 -g 0 -n -m
	mref=${mref}_brain
fi

## 02. Anat Coreg

anat2mref=${anat}2${mrefsfx}0GenericAffine

if [[ ! -e "../reg/${anat2mref}.mat" ]]
then
	echo "Coregistering ${func} to ${anat}"
	flirt -in ${anat}_brain -ref ${mref} -out ${tmp}/${anat}2${mrefsfx} -omat ${tmp}/${anat}2${mrefsfx}_fsl.mat \
	-searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ${mref} -src ${anat}_brain \
	${tmp}/${anat}2${mrefsfx}_fsl.mat -fsl2ras -oitk ${tmp}/${anat2mref}.mat
	anat2mref=${tmp}/${anat2mref}
else
	anat2mref=../reg/${anat2mref}
fi
if [[ "${adir}" != "none" ]]; then aseg=${adir}/${aseg}; fi
if [[ ! -e "${aseg}_seg2mref.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${func}"
	antsApplyTransforms -d 3 -i ${aseg}_seg.nii.gz \
						-r ${mref}.nii.gz -o ${tmp}/seg2mref.nii.gz \
						-n Multilabel -v \
						-t ${anat2mref}.mat \
						-t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]
	seg=${tmp}/seg2mref
else
	seg=${aseg}_seg2mref
fi

#Plot some grayplots!
3dGrayplot -input ${func_in}.nii.gz -mask ${seg}.nii.gz \
		   -prefix ${func}_gp_PVO.png -dimen 1800 1200 \
		   -polort ${pol} -pvorder -percent -range 3
3dGrayplot -input ${func_in}.nii.gz -mask ${seg}.nii.gz \
		   -prefix ${func}_gp_IJK.png -dimen 1800 1200 \
		   -polort ${pol} -ijkorder -percent -range 3
3dGrayplot -input ${func_in}.nii.gz -mask ${seg}.nii.gz \
		   -prefix ${func}_gp_peel.png -dimen 1800 1200 \
		   -polort ${pol} -peelorder -percent -range 3

cd ${cwd}