#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr"
echo "Optional:"
echo "anat scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=sub-${sub}_ses-01_T2w
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/02.func_preproc
debug=no

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;

		-anat)		anat=$2;shift;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;
		-debug)		debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr
scriptdir=${scriptdir%/}
checkoptvar anat scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
anat=${anat%.nii*}

#Derived variables
fileprx=sub-${sub}_ses-${ses}
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
fmapdir=${wdr}/sub-${sub}/ses-${ses}/fmap
fdir=${wdr}/sub-${sub}/ses-${ses}/func
### Cath errors and exit on them
set -e
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

sbref=${fileprx}_task-breathhold_rec-magnitude_echo-1_sbref
if [[ ! -e ${sbref}_cr.nii.gz ]]
then
	${scriptdir}/01.func_correct.sh -func_in ${sbref} -fdir ${fdir} -tmp ${tmp}
fi

echo "************************************"
echo "*** Func pepolar breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

${scriptdir}/02.func_pepolar.sh -func_in ${sbref}_cr -fdir ${fdir} \
								-breverse ${brev} -bforward ${bfor} \
								-tmp ${tmp}

echo "************************************"
echo "*** Func spacecomp breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

${scriptdir}/11.sbref_spacecomp.sh -sbref_in ${sbref}_tpp -anat ${anat} \
								   -fdir ${fdir}

sbreffunc=${fdir}/$( basename ${sbref} )

# Copy this sbref to reg folder
echo "imcp ${sbref}_tpp ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref"
imcp ${sbref}_tpp ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref

echo "imcp ${sbreffunc}_brain ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain"
imcp ${sbreffunc}_brain ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain
echo "imcp ${sbreffunc}_brain_mask ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain_mask"
imcp ${sbreffunc}_brain_mask ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_brain_mask

echo "if_missing_do mkdir ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup"
if_missing_do mkdir ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup

echo "cp -R ${sbreffunc}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/."
cp -R ${sbreffunc}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/.

[[ ${debug} == "yes" ]] && set +x

exit 0