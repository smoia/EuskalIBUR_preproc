#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
fs_json=none
anat=none
aseg=none
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

		-fs_json)	fs_json=$2;shift;;
		-anat)		anat=$2;shift;;
		-aseg)		aseg=$2;shift;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;
		-debug)		debug=yes;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr
scriptdir=${scriptdir%/}
checkoptvar fs_json anat scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat aseg
do
	eval "${var}=$( removeniisfx ${!var})"
done

#Derived variables

if [[ ${fs_json} != "none" ]]; then pepolarsfx=$(parse_filename_from_json pepolar ${fs_json}); else pepolarsfx=acq-breathhold_dir-PA_epi; fi
if [[ ${fs_json} != "none" ]]; then sbrefsfx=$(parse_filename_from_json sbref ${fs_json}); else sbrefsfx=task-breathhold_rec-magnitude_echo-1_sbref; fi

fileprx=sub-${sub}_ses-${ses}
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
fmapdir=${wdr}/sub-${sub}/ses-${ses}/fmap
fdir=${wdr}/sub-${sub}/ses-${ses}/func
func_in=${fileprx}_${pepolarsfx}
sbref=${fileprx}_${sbrefsfx}

### Cath errors and exit on them
set -e
######################################
#########    SBRef preproc   #########
######################################

echo ""
echo "Make sure system python is used by prepending /usr/bin to PATH"
[[ "${PATH%%:*}" != "/usr/bin" ]] && export PATH=/usr/bin:$PATH
echo "PATH is set to $PATH"
echo ""

filedirsfx=$( basename ${func_in#*_dir-*_} )
filedirprx=${func_in%_dir-*}
fordir=$( basename ${func_in#*_dir-} )
fordir=${fordir%_"$filedirsfx"}
revdir=$( echo ${fordir} | rev )

# Start funcpreproc by preparing the sbref.
for d in ${fordir} ${revdir}
do
	echo "************************************"
	echo "*** Func correct epi PE ${d}"
	echo "************************************"
	echo "************************************"

	func=${filedirprx}_dir-${d}_${filedirsfx}
	${scriptdir}/01.func_correct.sh -func_in ${func} -fdir ${fmapdir} -tmp ${tmp}
done

bfor=${filedirprx}_dir-${fordir}_${filedirsfx}_cr
brev=${filedirprx}_dir-${revdir}_${filedirsfx}_cr

echo "************************************"
echo "*** Func correct breathhold SBREF echo 1"
echo "************************************"
echo "************************************"

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
								   -fdir ${fdir} -aseg ${aseg} -use_bbr -tmp ${tmp}

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