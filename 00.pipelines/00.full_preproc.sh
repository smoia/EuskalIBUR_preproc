#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $(dirname "$0")/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses task TEs wdr"
echo "Optional:"
echo "anatsfx asegsfx voldiscard sbref mask slicetimeinterp despike fwhm scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
overwrite=yes
run_anat=yes
run_sbref=yes
anat1sfx=acq-uni_T1w
anat2sfx=none
TEs="10.6 28.69 46.78 64.87 82.96"
tasks="motor simon pinel breathhold"  #none
rs_runs=4  #none

std=MNI152_T1_1mm_brain
mmres=2.5
normalise=no
voldiscard=10
slicetimeinterp=no
despike=no
sbref=default
mask=default
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
[[ ${scriptdir: -1} == / ]] && scriptdir=${scriptdir%/*/} || scriptdir=${scriptdir%/*}
scriptdir=${scriptdir}/02.func_preproc
debug=no
fwhm=none

# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;
		-prjname)	prjname=$2;shift;;

		-TEs)				TEs="$2";shift;;
		-tasks)				tasks="$2";shift;;
		-rs_runs)			rs_runs="$2";shift;;
		-anat1sfx)			anat1sfx=$2;shift;;
		-anat2sfx)			anat2sfx=$2;shift;;
		-std)				std=$2;shift;;
		-mmres)				mmres=$2;shift;;
		-normalise) 		normalise=yes;;
		-voldiscard)		voldiscard=$2;shift;;
		-sbref)				sbref=$2;shift;;
		-mask)				mask=$2;shift;;
		-fwhm)				fwhm=$2;shift;;
		-slicetimeinterp)	slicetimeinterp=yes;;
		-despike)			despike=yes;;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-overwrite)			overwrite=yes;;
		-run_anat)			run_anat=yes;;
		-run_sbref)			run_sbref=yes;;
		-debug)				debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
checkreqvar sub ses task TEs wdr
[[ ${sbref} == "default " ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${mask} == "default " ]] && mask=${sbref}_brain_mask
checkoptvar anatsfx asegsfx voldiscard sbref mask slicetimeinterp despike fwhm scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat1sfx anat2sfx std sbref mask
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
fileprx=sub-${sub}_ses-${ses}
logprx=sub-${sub}_ses-${ses}
[[ ${anat1sfx} != none ]] && anat1=${wdr}/sub-${sub}/ses-${ses}/anat/${fileprx}_${anat1sfx} || anat1=none
[[ ${anat2sfx} != none ]] && anat2=${wdr}/sub-${sub}/ses-${ses}/anat/${fileprx}_${anat2sfx} || anat2=none
fdir=${wdr}/sub-${sub}/ses-${ses}/func
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}

first_ses_path=${wdr}/derivatives/${prjname}/sub-${sub}/ses-01
uni_sbref=${first_ses_path}/reg/sub-${sub}_sbref
uni_adir=${first_ses_path}/anat

####################

######################################
######### Script starts here #########
######################################

# Preparing log folder and log file, removing the previous one
if_missing_do mkdir ${wdr}/log
replace_and touch ${wdr}/log/${logprx}_preproc_logì

echo "************************************" >> ${wdr}/log/${logprx}_preproc_log

exec 3>&1 4>&2

exec 1>${wdr}/log/${logprx}_log 2>&1

date
echo "************************************"


echo "************************************"
echo "***    Preproc ${logprx}    ***"
echo "************************************"
echo "************************************"
echo ""
echo ""

######################################
#########   Prepare folders  #########
######################################

runprepfld="${scriptdir}/prepare_folder.sh -sub ${sub} -ses ${ses}"
runprepfld="${runprepfld} -wdr ${wdr} -std ${std} -mmres ${mmres}"
runprepfld="${runprepfld} -tmp ${tmp}"
if [[ "${overwrite}" == "yes" ]]
then
	runprepfld="${runprepfld} -overwrite"
	run_anat=yes
	run_sbref=yes
fi

eval ${runprepfld}

wdr=${wdr}/derivatives/${prjname}
tmp=${tmp}/tmp_${prjname}
######################################
#########    Anat preproc    #########
######################################

if [[ "${run_anat}" == "yes" ]]
then
	if [ ${ses} -eq 1 ]
	then
		# If asked & it's ses 01, run anat
		${scriptdir}/00.pipelines/anat_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} \
												  -anat1sfx ${anat1sfx} -anat2sfx ${anat2sfx} \
												  -std ${std} -mmres ${mmres} -normalise \
												  -tmp ${tmp}
	elif [ ${ses} -lt 1 ]
	then
		echo "ERROR: the session number introduced makes no sense."
		echo "Please run a positive numbered session."
		exit 1
	elif [ ! -d ${uni_adir} ]
	then
		# If it isn't ses 01 but that ses wasn't run, exit.
		echo "ERROR: the universal anat_preproc folder,"
		echo "   ${uni_adir}"
		echo "doesn't exist. For the moment, this means the program quits"
		echo "Please run the first session of each subject first"
		exit 1
	elif [ -d ${uni_adir} ]
	then
		# If it isn't ses 01, and that ses was run, copy relevant files.
		mkdir -p ${wdr}/sub-${sub}/ses-${ses}/anat
		cp -R ${uni_adir}/* ${wdr}/sub-${sub}/ses-${ses}/anat/.
		# Then be sure that the anatomical files reference is right.
		anat1=sub-${sub}_ses-01_acq-uni_T1w 
		cp ${uni_adir}/../reg/*${anat1}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		if [[ ${anat2} != "none" ]]
		then
			anat2=sub-${sub}_ses-01_T2w
			cp ${uni_adir}/../reg/*${anat2}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		fi
	fi
fi


######################################
#########    SBRef preproc   #########
######################################

if [[ "${run_sbref}" == "yes" ]]
then
	if [ ${ses} -eq 1 ]
	then
		# If asked & it's ses 01, run sbref
		${scriptdir}/00.pipelines/sbref_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} \
												   -anat ${anat2} -tmp ${tmp}
	elif [ ${ses} -lt 1 ]
	then
		echo "ERROR: the session number introduced makes no sense."
		echo "Please run a positive numbered session."
		exit 1
	elif [ ! -e "${uni_sbref}.nii.gz" ]
	then
		# If it isn't ses 01 but that ses wasn't run, exit.
		echo "ERROR: the universal sbref,"
		echo "   ${uni_sbref}.nii.gz"
		echo "doesn't exist. For the moment, this means the program quits"
		echo "Please run the first session of each subject first"
		exit
	elif [ -e "${uni_sbref}.nii.gz" ]
	then
		# If it isn't ses 01, and that ses was run, copy relevant files.
		cp ${uni_sbref}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		[[ ${anat2} != "none" ]] && imcp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref

		mkdir ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup
		cp -R ${uni_sbref}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/.

		cp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref_fsl.mat \
		   ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref_fsl.mat
		cp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref0GenericAffine.mat \
		   ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref0GenericAffine.mat
	fi
fi


######################################
#########    Task preproc    #########
######################################

aseg=sub-${sub}_ses-01_acq-uni_T1w 
anat=sub-${sub}_ses-01_T2w

for task in motor pinel simon
do
	${scriptdir}/00.pipelines/task_preproc.sh ${sub} ${ses} ${task} ${wdr} ${anat} ${aseg} \
										  ${fdir} ${vdsc} "${TEs}" \
										  ${nTE} ${siot} ${dspk} /scripts ${tmp}
done


######################################
#########    Rest preproc    #########
######################################

for run in 01 02 03 04
do
	${scriptdir}/00.pipelines/rest_full_preproc.sh ${sub} ${ses} ${run} ${wdr} ${anat} ${aseg} \
										       ${fdir} ${vdsc} "${TEs}" \
										       ${nTE} ${siot} ${dspk} /scripts ${tmp}
done


date
echo "************************************"
echo "************************************"
echo "***      Preproc COMPLETE!       ***"
echo "************************************"
echo "************************************"