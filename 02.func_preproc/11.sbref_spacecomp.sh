#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
anat_in=none
aseg_in=none
bbr=no
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sbref_in)	sbref_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)		anat_in=$2;shift;;
		-aseg)		aseg_in=$2;shift;;
		-use_bbr)	bbr=yes;;			# Use BBR+NMI registration from sbref to anat (requires segmentation), otherwise use NMI registration from anat to sbref
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar sbref_in fdir
checkoptvar anat_in aseg_in bbr tmp

### Remove nifti suffix
for var in sbref_in anat_in aseg_in
do
	eval "${var}=$( removeniisfx ${!var})"
done

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
sbref=$( basename ${sbref_in%_*} )
if_missing_do mkdir ../reg

## 01. BET
echo "BETting ${sbref}"
brain_extract -nii ${sbref_in} -method fsss -tmp ${tmp}
mv ${sbref_in}_brain.nii.gz ${sbref}_brain.nii.gz
mv ${sbref_in}_brain_mask.nii.gz ${sbref}_brain_mask.nii.gz

cp ${sbref}_brain*.nii.gz ../reg/.

## 02. Anat Coreg
aseg_in=${aseg_in%_seg}
aseg=$( basename ${aseg_in} )
asegsfx=${aseg#*ses-*_}

anat=$( basename ${anat_in} )
anatsfx=${anat#*ses-*_}

anat2sbref=../reg/${anat}2sbref0GenericAffine.mat

if [[ "${anat}" != "none" && "${anat_in}" != "${aseg_in}" && ! -e "../reg/${anat}2${asegsfx}0GenericAffine.mat" ]]
then
	echo "!!! Warning: provided anat and aseg are different volumes, but no registration matrix between the two was found. Setting aseg to none to avoid issues in later stages !!!"
	aseg=none
fi

if [[ "${aseg}" != "none" && ! -e "${aseg_in}_seg.nii.gz" ]]
then
	echo "Segmentation ${aseg_in}_seg.nii.gz could not be found. Setting aseg to none."
	aseg=none
fi

if [[ "${anat}" != "none" ]]
then
	if_missing_do stop ${anat_in}_brain.nii.gz

	if [[ "${bbr}" == "yes" && "${aseg}" != "none" ]]
	then
		echo "Coregistering ${sbref} to ${anat} using normalised BBR search cost, normalised MI cost, and 6 DoFs (Rigid body)"
		# Extract WM, then make sure it's in anat space
		fslmaths ${aseg_in}_seg.nii.gz -thr 3 ${tmp}/${aseg}_wm.nii.gz
		[[ "${anat}" != "${aseg}" ]] && antsApplyTransforms -d 3 -i ${tmp}/${aseg}_wm.nii.gz -r ${anat_in}_brain.nii.gz -o ${tmp}/${anat}_wm.nii.gz -n NearestNeighbor -v -t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]

		flirt -in ${sbref}_brain -ref ${anat_in}_brain -out ../reg/${sbref}2${anatsfx}_fsl -omat ../reg/${sbref}2${anatsfx}_fsl.mat \
			  -searchcost bbr -cost normmi -wmseg ${tmp}/${anat}_wm.nii.gz -dof 6 -searchry -90 90 -searchrx -90 90 -searchrz -90 90

		echo "Inverting matrix to coregister ${anat} to ${sbref}"
		
		convert_xfm -omat ../reg/${anat}2sbref_fsl.mat -inverse ../reg/${sbref}2${anatsfx}_fsl.mat
		flirt -init ../reg/${anat}2sbref_fsl.mat -applyxfm -in ${anat_in}_brain -ref ${sbref}_brain -o ../reg/${anat}2sbref_fsl
	else
		echo "Coregistering ${anat} to ${sbref} using normalised MI cost and 6 DoFs (Rigid body)"
		flirt -in ${anat_in}_brain -ref ${sbref}_brain -out ../reg/${anat}2sbref_fsl -omat ../reg/${anat}2sbref_fsl.mat \
			  -searchry -90 90 -searchrx -90 90 -searchrz -90 90 -cost normmi -searchcost normmi -dof 6
	fi
	echo "Trasforming matrix from FSL to ANTs"
	c3d_affine_tool -ref ${sbref}_brain -src ${anat_in}_brain ../reg/${anat}2sbref_fsl.mat -fsl2ras -oitk ../reg/${anat}2sbref0GenericAffine.mat
	antsApplyTransforms -d 3 -i ${anat_in}_brain.nii.gz \
						-r ${sbref}_brain.nii.gz -o ../reg/${anat}2sbref.nii.gz \
						-n Linear -t ${anat2sbref}
fi

cd ${cwd}