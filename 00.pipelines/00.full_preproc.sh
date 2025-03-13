#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses prjname wdr"
echo "Optional:"
echo "TEs tasks anat1sfx anat2sfx fs_json std mmres skip_normalisation voldiscard sbref mask "
echo "fwhm slicetimeinterp despike skip_meicaden scriptdir tmp overwrite skip_prep skip_anat "
echo "skip_sbref only_echoes only_optcom optcom_and_2e skip_greyplots debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
overwrite=no
run_prep=yes
run_anat=yes
run_sbref=yes
anat1sfx=acq-uni_T1w
anat2sfx=T2w
fs_json=none
TEs="10.6 28.69 46.78 64.87 82.96"
tasks="motor simon pinel breathhold rest_run-01 rest_run-02 rest_run-03 rest_run-04"  #none

std=MNI152_T1_1mm_brain
mmres=2.5
normalise=yes
voldiscard=10
slicetimeinterp=none
despike=no
den_meica=yes
sbref=default
mask=default
preproc_echoes=yes
preproc_optcom=yes
greyplot=yes
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
debug=no
fwhm=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
printcall="${printline} $*"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;
		-prjname)	prjname=$2;shift;;

		-TEs)					TEs="$2";shift;;
		-tasks)					tasks="$2";shift;;
		-anat1sfx)				anat1sfx=$2;shift;;
		-anat2sfx)				anat2sfx=$2;shift;;
		-fs_json)				fs_json=$2;shift;;
		-std)					std=$2;shift;;
		-mmres)					mmres=$2;shift;;
		-skip_normalisation)	normalise=no;;
		-voldiscard)			voldiscard=$2;shift;;
		-sbref)					sbref=$2;shift;;
		-mask)					mask="$2";shift;;
		-fwhm)					fwhm="$2";shift;;
		-slicetimeinterp)		slicetimeinterp="$2";shift;;
		-despike)				despike=yes;;
		-skip_meicaden)			den_meica=no;;
		-scriptdir)				scriptdir=$2;shift;;
		-tmp)					tmp=$2;shift;;
		-overwrite)				overwrite=yes;;
		-skip_prep)				run_prep=no;;
		-skip_anat)				run_anat=no;;
		-skip_sbref)			run_sbref=no;;
		-only_echoes)			preproc_optcom=no;;
		-only_optcom)			preproc_echoes=no;;
		-optcom_and_2e)			preproc_echoes=second; preproc_optcom=yes;;
		-skip_greyplots)		greyplot=no;;
		-debug)					debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr prjname
scriptdir=${scriptdir%/}
checkoptvar TEs tasks anat1sfx anat2sfx fs_json std mmres normalise voldiscard sbref \
			mask fwhm slicetimeinterp despike den_meica scriptdir tmp overwrite run_prep \
			run_anat run_sbref preproc_optcom preproc_echoes greyplot debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in std sbref mask
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
first_ses_path=${wdr}/derivatives/${prjname}/sub-${sub}/ses-01
uni_sbref=${first_ses_path}/reg/sub-${sub}_sbref
uni_adir=${first_ses_path}/anat

####################

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

# Preparing log folder and log file, removing the previous one
if_missing_do mkdir ${wdr}/log
logfile=${wdr}/log/sub-${sub}_ses-${ses}_${prjname}_preproc_log


replace_and touch ${logfile}

echo "************************************" >> ${logfile}

exec 3>&1 4>&2

exec 1>${logfile} 2>&1

date
echo ""
echo ${printcall}
echo ""
checkreqvar sub ses prjname wdr
checkoptvar anat1sfx anat2sfx fs_json voldiscard sbref mask slicetimeinterp despike fwhm scriptdir tmp debug

echo "************************************"

echo ""
echo ""

echo "************************************"
echo "***    Preproc sub ${sub} ses ${ses} ${prjname}"
echo "************************************"
echo "************************************"
echo ""
echo ""

######################################
#########   Prepare folders  #########
######################################

if [[ "${run_prep}" == "yes" ]]
then
	runprepfld="${scriptdir}/../prepare_folder.sh -sub ${sub} -ses ${ses}"
	runprepfld="${runprepfld} -wdr ${wdr} -std ${std} -mmres ${mmres}"
	runprepfld="${runprepfld} -tmp ${tmp} -prjname ${prjname}"
	runprepfld="${runprepfld} -tasks ${tasks}"
	if [[ "${overwrite}" == "yes" ]]
	then
		runprepfld="${runprepfld} -overwrite"
		run_anat=yes
		run_sbref=yes
	fi

	echo "# Generating the command:"
	echo ""
	echo "${runprepfld}"
	echo ""

	eval ${runprepfld}
fi

wdr=${wdr}/derivatives/${prjname}
tmp=${tmp}/tmp_${prjname}_${sub}_${ses}

######################################
#########    Anat preproc    #########
######################################

echo ""
echo ""

[[ ${fs_json} != "none" ]] && anat1sfx=$(parse_filename_from_json ${anat1} ${fs_json})
[[ ${fs_json} != "none" ]] && anat2sfx=$(parse_filename_from_json ${anat2} ${fs_json})

if [[ ${anat1sfx} != "none" ]]; then anat1=sub-${sub}_ses-01_${anat1sfx}; else anat1=none; fi
if [[ ${anat2sfx} != "none" ]]; then anat2=sub-${sub}_ses-01_${anat2sfx}; else anat2=none; fi

if [[ "${run_anat}" == "yes" ]]
then
	if [ ${ses} -eq 1 ]
	then
		# If asked & it's ses 01, run anat
		runanatpreproc="${scriptdir}/anat_preproc.sh -sub ${sub} -ses ${ses}"
		runanatpreproc="${runanatpreproc} -wdr ${wdr} -std ${std} -mmres ${mmres}"
		runanatpreproc="${runanatpreproc} -anat1sfx ${anat1sfx} -anat2sfx ${anat2sfx}"
		runanatpreproc="${runanatpreproc} -tmp ${tmp}"
		
		[[ ${normalise} == "yes" ]] && runanatpreproc="${runanatpreproc} -normalise"

		echo "# Generating the command:"
		echo ""
		echo "${runanatpreproc}"
		echo ""

		eval ${runanatpreproc}

	elif [ ${ses} -lt 1 ]
	then
		echo "ERROR: the session number introduced makes no sense."
		echo "Please run a positive numbered session."
		exit 1
	elif [ ! -d ${uni_adir} ]
	then
		# If it isn't ses 01 but that ses wasn't run, exit.
		echo "ERROR: the universal anat folder,"
		echo "   ${uni_adir}"
		echo "doesn't exist. For the moment, this means the program quits"
		echo "Please run the first session of each subject first"
		exit 1
	elif [ -d ${uni_adir} ]
	then
		echo ""
		echo "Copy anatomical files from sessions 01"
		echo ""
		# If it isn't ses 01, and that ses was run, copy relevant files.
		mkdir -p ${wdr}/sub-${sub}/ses-${ses}/anat
		cp -R ${uni_adir}/* ${wdr}/sub-${sub}/ses-${ses}/anat/.
		# Then be sure that the anatomical files reference is right.
		cp ${uni_adir}/../reg/*${anat1}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		if [[ ${anat2} != "none" ]]
		then
			cp ${uni_adir}/../reg/*${anat2}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		fi
	fi
fi


######################################
#########    SBRef preproc   #########
######################################

echo ""
echo ""

aseg=${uni_adir}/${anat1}
anat=${uni_adir}/${anat2}

if [[ "${run_sbref}" == "yes" ]]
then
	if [ ${ses} -eq 1 ]
	then
		# If asked & it's ses 01, run sbref
		${scriptdir}/sbref_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} \
									  -anat ${anat} -tmp ${tmp}
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
		echo ""
		echo "Copy SBRef files from sessions 01"
		echo ""
		# If it isn't ses 01, and that ses was run, copy relevant files.
		mkdir -p ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup
		cp -R ${uni_sbref}_topup/* ${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref_topup/.

		cp -R ${uni_sbref}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		[[ ${anat2} != "none" ]] && imcp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref

		cp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref_fsl.mat \
		   ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref_fsl.mat
		cp ${wdr}/sub-${sub}/ses-01/reg/${anat2}2sbref0GenericAffine.mat \
		   ${wdr}/sub-${sub}/ses-${ses}/reg/${anat2}2sbref0GenericAffine.mat
	fi
fi


######################################
#########    Task preproc    #########
######################################

echo ""
echo ""

aseg=${uni_adir}/${anat1}
anat=${uni_adir}/${anat2}
[[ ${sbref} == "default" ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${mask} == "default" ]] && mask=${sbref}_brain_mask

if [[ ${tasks} != "none" ]]
then
	for task in ${tasks}
	do
		runfuncpreproc="${scriptdir}/func_preproc.sh -sub ${sub} -ses ${ses}"
		runfuncpreproc="${runfuncpreproc} -task ${task} -TEs \"${TEs}\""
		runfuncpreproc="${runfuncpreproc} -wdr ${wdr} -anat ${anat} -aseg ${aseg}"
		runfuncpreproc="${runfuncpreproc} -voldiscard ${voldiscard} -slicetimeinterp ${slicetimeinterp}"
		runfuncpreproc="${runfuncpreproc} -sbref ${sbref}"
		runfuncpreproc="${runfuncpreproc} -mask ${mask} -fwhm ${fwhm} -tmp ${tmp}"
		runfuncpreproc="${runfuncpreproc} -den_motreg -den_detrend"

		[[ ${preproc_optcom} == "no" ]] && runfuncpreproc="${runfuncpreproc} -only_echoes"
		[[ ${preproc_echoes} == "no" ]] && runfuncpreproc="${runfuncpreproc} -only_optcom"
		[[ ${preproc_echoes} == "second" ]] && runfuncpreproc="${runfuncpreproc} -optcom_and_2e"
		[[ ${greyplot} == "no" ]] && runfuncpreproc="${runfuncpreproc} -skip_greyplots"

		[[ ${despike} == "yes" ]] && runfuncpreproc="${runfuncpreproc} -despike"
		if [[ ${task} != "breathhold" ]]
		then
			[[ ${den_meica} == "yes" ]] && runfuncpreproc="${runfuncpreproc} -den_meica"
			if [[ ${task} == *"rest"* ]]
			then
				runfuncpreproc="${runfuncpreproc} -applynuisance"
			fi
		fi

		echo "# Generating the command:"
		echo ""
		echo "${runfuncpreproc}"
		echo ""

		eval ${runfuncpreproc}
	done
fi

echo ""
echo ""

date
echo "************************************"
echo "************************************"
echo "***      Preproc COMPLETE!       ***"
echo "************************************"
echo "************************************"

if [[ ${debug} == "yes" ]]; then set +x; else rm -rf ${tmp}; fi