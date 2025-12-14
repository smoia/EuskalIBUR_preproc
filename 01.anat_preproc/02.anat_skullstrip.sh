#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
mask=none
masksource_in=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-anat_in)	anat_in=$2;shift;;
		-adir)		adir=$2;shift;;

		-mask)			mask=$2;shift;;				# Specify an external mask.
		-masksource)	masksource_in=$2;shift;;	# Specify another file from where to take a mask to apply to this anatomical. A transformation matrix from it must exist for this.

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar anat_in adir
checkoptvar mask masksource_in

### Remove nifti suffix
for var in anat_in mask masksource_in
do
	eval "${var}=${!var%.nii*}"
done

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${adir} || exit

#Read and process input
anat=$( basename ${anat_in%_*} )
anatsfx=${anat#*ses-*_}

# First check if there is a mask source, if so, bring that mask in anat.
masksource=$( basename ${masksource_in%_mask} )
# Specifically remove _brain_mask if specified - _mask was already removed if present.
masksource=${masksource%_brain}

if [[ "${masksource}" != "none" ]] && [[ -e ../reg/${masksource}2${anatsfx}0GenericAffine.mat ]]
then
	# If a reference is specified, coreg the mask to the reference
	echo "Flirting ${masksource} into ${anat}"
	antsApplyTransforms -d 3 -i ${masksource}_brain_mask.nii.gz \
						-r ${anat_in}.nii.gz -o ${anat}_brain_mask.nii.gz \
						-n NearestNeighbor -t ../reg/${masksource}2${anatsfx}0GenericAffine.mat
	mask=${anat}_brain_mask
fi

if [[ "${mask}" == "none" ]]
then
	# If no mask is specified, create it.
	echo "Skull Stripping ${anat}"

	# This comes from utils.sh
	brain_extract -nii ${anat_in} -method 3dss -tmp ${adir}
	mv ${anat_in}_brain.nii.gz ${anat}_brain.nii.gz
	mv ${anat_in}_brain_mask.nii.gz ${anat}_brain_mask.nii.gz
	echo ""
else
	# If a mask is specified, use it.
	# Check if user input is basename or mask itself.
	if [[ -e "${mask}_brain_mask.nii.gz" ]]
	then
		mask=${mask}_brain_mask
	fi
	echo "Masking ${anat}"
	fslmaths ${anat_in} -mas ${mask} ${anat}_brain
	fslmaths ${anat}_brain -bin ${anat}_brain_mask  # Just to be sure!
fi

# If a masksource was specified, register the brain to that one.
if [[ "${masksource}" != "none" ]]
then
	masksourcesfx=${masksource#*ses-*_}
	antsApplyTransforms -d 3 -i ${anat}_brain.nii.gz \
						-r ${masksource}_brain.nii.gz -o ../reg/${anat}_brain2${masksourcesfx}_brain.nii.gz \
						-n Linear -t [../reg/${masksource}2${anatsfx}0GenericAffine.mat,1]
fi

cd ${cwd}