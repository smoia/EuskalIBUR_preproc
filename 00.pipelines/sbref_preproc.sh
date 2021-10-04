#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $(dirname "$0")/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr"
echo "Optional:"
echo "anatsfx scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anatsfx=T2w
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
[[ ${scriptdir: -1} == / ]] && scriptdir=${scriptdir%/*/} || scriptdir=${scriptdir%/*}
scriptdir=${scriptdir}/02.func_preproc
debug=no

# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;

		-anatsfx)	anatsfx=$2;shift;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;
		-debug)		debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
checkreqvar sub ses wdr
checkoptvar anatsfx scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
anatsfx=${anatsfx%.nii*}

#Derived variables
fileprx=sub-${sub}_ses-${ses}
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
anat=${fileprx}_${anatsfx}
adir=${wdr}/sub-${sub}/ses-${ses}/anat
fmapdir=${wdr}/sub-${sub}/ses-${ses}/fmap
fdir=${wdr}/sub-${sub}/ses-${ses}/func
######################################
#########    SBRef preproc   #########
######################################

# Start funcpreproc by preparing the sbref.
for d in AP PA
do
	echo "************************************"
	echo "*** Func correct breathhold PE ${d}"
	echo "************************************"
	echo "************************************"

	func=${fileprx}_acq-breathhold_dir-${d}_epi
	${scriptdir}/01.func_correct.sh -func_in ${func} -fdir ${fmapdir} -tmp ${tmp}
done

bfor=${fileprx}_acq-breathhold_dir-PA_epi_cr
brev=${fileprx}_acq-breathhold_dir-AP_epi_cr

echo "************************************"
echo "*** Func correct breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

sbrf=${fileprx}_task-breathhold_rec-magnitude_echo-1_sbref
if [[ ! -e ${sbrf}_cr.nii.gz ]]
then
	${scriptdir}/01.func_correct.sh -func_in ${sbrf} -fdir ${fdir} -tmp ${tmp}
fi

echo "************************************"
echo "*** Func pepolar breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

${scriptdir}/02.func_pepolar.sh -func_in ${sbrf}_cr -fdir ${fdir} \
								-breverse ${brev} -bforward ${bfor} -tmp ${tmp}

echo "************************************"
echo "*** Func spacecomp breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

${scriptdir}/11.sbref_spacecomp.sh -sbref_in ${sbrf}_tpp -anat ${anat} \
								   -fdir ${fdir} -adir ${adir} -tmp ${tmp}

# Copy this sbref to reg folder
echo "imcp ${fdir}/${sbrf}_tpp ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref"
imcp ${fdir}/${sbrf}_tpp ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
echo "imcp ${fdir}/${sbrf}_brain ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain"
imcp ${fdir}/${sbrf}_brain ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain
echo "imcp ${fdir}/${sbrf}_brain_mask ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain_mask"
imcp ${fdir}/${sbrf}_brain_mask ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain_mask
echo "imcp ${fdir}/${anat}2${sbrf}.nii.gz ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref"
imcp ${fdir}/${anat}2${sbrf}.nii.gz ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref

echo "mkdir ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup"
mkdir ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup
echo "cp -R ${fdir}/${sbrf}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/."
cp -R ${fdir}/${sbrf}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/.
echo "cp ${fdir}/${anat}2${sbrf}_fsl.mat ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref_fsl.mat"
cp ${fdir}/${anat}2${sbrf}_fsl.mat ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref_fsl.mat
echo "cp ${fdir}/${anat}2${sbrf}0GenericAffine.mat ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref0GenericAffine.mat"
cp ${fdir}/${anat}2${sbrf}0GenericAffine.mat ${wdr}/sub-${sub}/ses-${ses}/reg/${anat}2sub-${sub}_sbref0GenericAffine.mat

[[ ${debug} == "yes" ]] && set +x
