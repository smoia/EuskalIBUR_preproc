#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
anat_in=none
mref_in=none
aseg_in=none
antsrealign=no
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
		-func_in)	func_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)			anat_in=$2;shift;;
		-mref)			mref_in=$2;shift;;
		-aseg)			aseg_in=$2;shift;;
		-antsrealign)	antsrealign=yes;;	# Convert all motion realignment matrices to ANTs
		-use_bbr)		bbr=yes;;			# Use BBR+NMI registration from sbref to anat (requires segmentation), otherwise use NMI registration from anat to sbref
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar anat_in mref_in aseg_in antsrealign use_bbr tmp

### Remove nifti suffix
for var in func_in anat_in mref_in aseg_in
do
	eval "${var}=$( removeniisfx ${!var} )"
done

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

if_missing_do mkdir ../reg

#Read and process input
func=$( basename ${func_in%_*} )

nTR=$(fslval ${func_in} dim4)
let nTR--

## 01. Motion Computation, if more than 1 volume
mref=$( basename ${mref_in} )


if [[ ${nTR} -gt 1 ]]
then
	# 01.1. Mcflirt
	if [[ "${mref_in}" == "none" ]]
	then
		echo "Creating a reference for ${func}"
		mref_in=${func}_avgref
		fslmaths ${func_in} -Tmean ${mref_in}
	fi

	echo "McFlirting ${func}"
	if [[ -d ${tmp}/${func}_mcf.mat ]]; then rm -r ${tmp}/${func}_mcf.mat; fi
	mcflirt -in ${func_in} -r ${mref_in} -out ${tmp}/${func}_mcf -stats -mats -plots

	# 01.2. Demean motion parameters
	echo "Demean and derivate ${func} motion parameters"
	1d_tool.py -infile ${tmp}/${func}_mcf.par -demean -write ${func}_mcf_demean.par -overwrite
	1d_tool.py -infile ${func}_mcf_demean.par -derivative -demean -write ${func}_mcf_deriv1.par -overwrite

	# 01.3. Compute various metrics
	echo "Computing DVARS and FD for ${func}"
	fsl_motion_outliers -i ${tmp}/${func}_mcf -o ${tmp}/${func}_mcf_dvars_confounds -s ${func}_dvars_post.par -p ${func}_dvars_post --dvars --nomoco
	fsl_motion_outliers -i ${func_in} -o ${tmp}/${func}_mcf_dvars_confounds -s ${func}_dvars_pre.par -p ${func}_dvars_pre --dvars --nomoco
	fsl_motion_outliers -i ${func_in} -o ${tmp}/${func}_mcf_fd_confounds -s ${func}_fd.par -p ${func}_fd --fd
fi

if [[ ! -e "${mref_in}_brain_mask" && "${mref_in}" != "none" ]]
then
	echo "BETting reference ${mref}"
	brain_extract -nii ${mref_in} -method fsss -tmp ${tmp}
fi

# 01.4. Apply mask
echo "BETting ${func}"
fslmaths ${tmp}/${func}_mcf -mas ${mref_in}_brain_mask ${tmp}/${func}_bet

## 02. Anat Coreg
mrefsfx=${mref#*ses-*_}

aseg=$( basename ${aseg_in} )
asegsfx=${aseg#*ses-*_}

anat=$( basename ${anat_in} )
anatsfx=${anat#*ses-*_}

anat2mref=../reg/${anat}2${mrefsfx}0GenericAffine.mat

if [[ "${anat}" != "none" && "${anat_in}" != "${aseg_in}" && ! -e "../reg/${anat}2${asegsfx}0GenericAffine.mat" ]]
then
	echo "!!! Warning: provided anat and aseg are different volumes, but no registration matrix between the two was found. Setting both to none to avoid issues in later stages !!!"
	anat=none
	aseg=none
fi

if [[ "${anat}" != "none" && ! -e "${anat2mref}" ]]
then
	if [[ "${bbr}" == "yes" && "${aseg}" != "none" && -e "../anat/${aseg}_seg.nii.gz" ]]
	then
		echo "Coregistering ${mref} to ${anat} using normalised BBR search cost, normalised MI cost, and 6 DoFs (Rigid body)"
		# Extract WM, then make sure it's in anat space
		fslmaths ../anat/${aseg}_seg.nii.gz -thr 3 ${tmp}/${aseg}_wm.nii.gz
		[[ "${anat}" != "${aseg}" ]] && antsApplyTransforms -d 3 -i ${tmp}/${aseg}_wm.nii.gz -r ${anat_in}_brain.nii.gz -o ${tmp}/${anat}_wm.nii.gz -n NearestNeighbor -v -t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]

		flirt -in ${mref_in}_brain -ref ${anat_in}_brain -out ../reg/${mref}2${anatsfx}_fsl -omat ../reg/${mref}2${anatsfx}_fsl.mat \
			  -searchcost bbr -cost normmi -wmseg ${tmp}/${anat}_wm.nii.gz -dof 6 -searchry -90 90 -searchrx -90 90 -searchrz -90 90

		echo "Inverting matrix to coregister ${anat} to ${mref}"
		
		convert_xfm -omat ../reg/${anat}2${mrefsfx}_fsl.mat -inverse ../reg/${mref}2${anatsfx}_fsl.mat
		flirt -init ../reg/${anat}2${mrefsfx}_fsl.mat -applyxfm -in ${anat_in}_brain -ref ${mref_in}_brain -o ../reg/${anat}2${mrefsfx}_fsl

	else
		echo "Coregistering ${anat} to ${mref} using normalised MI cost and 6 DoFs (Rigid body)"
		flirt -in ${anat_in}_brain -ref ${mref_in}_brain -out ../reg/${anat}2${mrefsfx}_fsl -omat ../reg/${anat}2${mrefsfx}_fsl.mat \
			  -searchry -90 90 -searchrx -90 90 -searchrz -90 90 -cost normmi -searchcost normmi -dof 6
	fi

	[[ "${aseg}" == "none" || ! -e "../anat/${aseg}_seg.nii.gz"  && "${bbr}" == "yes" ]] && echo "!!! Warning: You tried to use BBR, but either did not provide an anatomical segmentation, or the one you provided did not exist, or the necessary transformation did not exist !!!"

	echo "Trasforming matrix from FSL to ANTs"
	c3d_affine_tool -src ${anat_in}_brain -ref ${mref_in}_brain ../reg/${anat}2${mrefsfx}_fsl.mat -fsl2ras -oitk ${anat2mref}
	antsApplyTransforms -d 3 -i ${anat_in}_brain.nii.gz \
						-r ${mref_in}_brain.nii.gz -o ../reg/${anat}2${mrefsfx}.nii.gz \
						-n Linear -t ${anat2mref}
fi

if [[ "${aseg}" != "none" && -e "../anat/${aseg}_seg.nii.gz" && ! -e "../anat/${aseg}_seg2${mrefsfx}.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${mref}"
	runantsAT="antsApplyTransforms -d 3 -i ../anat/${aseg}_seg.nii.gz"
	runantsAT="${runantsAT} -r ${mref_in}_brain.nii.gz -o ../anat/${aseg}_seg2${mrefsfx}.nii.gz"
	runantsAT="${runantsAT} -n Multilabel -v"
	runantsAT="${runantsAT} -t ${anat2mref}"

	[[ "${anat}" != "${aseg}" ]] && runantsAT="${runantsAT} -t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]"

	echo ${runantsAT}
	eval ${runantsAT}
fi

## 03. Split and affine to ANTs if required
if [[ "${antsrealign}" == "yes" ]]
then
	echo "Trasforming matrix from FSL to ANTs"
	echo "Splitting ${func}"
	replace_and mkdir ${tmp}/${func}_split
	replace_and mkdir ../reg/${func}_mcf_ants_mat
	fslsplit ${func_in} ${tmp}/${func}_split/vol_ -t

	for i in $( seq -f %04g 0 ${nTR} )
	do
		echo "Trasforming matrix ${i} of ${nTR} in ${func}"
		c3d_affine_tool -ref ${mref_in}_brain -src ${tmp}/${func}_split/vol_${i}.nii.gz \
		${tmp}/${func}_mcf.mat/MAT_${i} -fsl2ras -oitk ../reg/${func}_mcf_ants_mat/v${i}2${mrefsfx}.mat
	done
	rm -r ${tmp}/${func}_split
fi

# Moving things around
[[ -d ../reg/${func}_mcf.mat ]] && rm -r ../reg/${func}_mcf.mat
mv ${tmp}/${func}_mcf.mat ../reg/.

[[ "${mref}" == "${func}_avgref" ]] && mv ${mref}* ../reg/.

cd ${cwd}