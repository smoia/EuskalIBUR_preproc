#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
fs_json=none
anat=none
aseg=none
voldiscard=10
polort=4
slicetimeinterp=none
despike=no
sbref=default
mask=default
den_motreg=no
den_detrend=no
den_meica=no
den_tissues=no
applynuisance=no
preproc_echoes=yes
preproc_optcom=yes
greyplot=yes
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/02.func_preproc
debug=no
fwhm=none

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
		-task)		task=$2;shift;;
		-TEs)		TEs="$2";shift;;
		-wdr)		wdr=$2;shift;;

		-fs_json)			fs_json=$2;shift;;
		-anat)				anat=$2;shift;;
		-aseg)				aseg=$2;shift;;
		-voldiscard)		voldiscard=$2;shift;;
		-polrot)			polort=$2;shift;;
		-sbref)				sbref=$2;shift;;
		-mask)				mask=$2;shift;;
		-fwhm)				fwhm=$2;shift;;
		-slicetimeinterp)	slicetimeinterp=$2;shift;;
		-despike)			despike=yes;;
		-den_motreg)		den_motreg=yes;;
		-den_detrend)		den_detrend=yes;;
		-den_meica)			den_meica=yes;;
		-den_tissues)		den_tissues=yes;;
		-applynuisance)		applynuisance=yes;;
		-only_echoes)		preproc_optcom=no;;
		-only_optcom)		preproc_echoes=no;;
		-optcom_and_2e)		preproc_echoes=second; preproc_optcom=yes;;
		-skip_greyplots)	greyplot=no;;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-debug)				debug=yes;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses task TEs wdr
scriptdir=${scriptdir%/}
[[ ${sbref} == "default" ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${mask} == "default" ]] && mask=${sbref}_brain_mask
checkoptvar fs_json anat aseg voldiscard polort sbref mask slicetimeinterp despike fwhm  \
			den_motreg den_detrend den_meica den_tissues applynuisance preproc_optcom \
			preproc_echoes greyplot scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat aseg
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables

if [[ ${fs_json} != "none" ]]; then boldsfx=$(parse_filename_from_json ${task} ${fs_json}); else boldsfx=echo-${e}_bold; fi
if [[ ${fs_json} != "none" ]]; then fmatsfx=$(parse_filename_from_json ${task}fmat ${fs_json}); else fmatsfx=echo-1_bold; fi

aTEs=( ${TEs} )
nTE=${#aTEs[@]}
fileprx=sub-${sub}_ses-${ses}
fdir=${wdr}/sub-${sub}/ses-${ses}/func
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
func_in=${fileprx}_task-${task}_${boldsfx}

### Cath errors and exit on them
set -e
######################################
#########    Task preproc    #########
######################################

echo ""
echo "Make sure system python is used by prepending /usr/bin to PATH"
[[ "${PATH%%:*}" != "/usr/bin" ]] && export PATH=/usr/bin:$PATH
echo "PATH is set to $PATH"
echo ""

# Find right filenames
fileechosfx=$( basename ${func_in#*_echo-*_} )
fileechoprx=${func_in%_echo-*}

for e in $( seq 1 ${nTE} )
do
	echo "************************************"
	echo "*** Func correct ${task} BOLD echo ${e}"
	echo "************************************"
	echo "************************************"

	echo "bold=${fileechoprx}_echo-${e}_${fileechosfx}"
	bold=${fileechoprx}_echo-${e}_${fileechosfx}
	runfunccorrect="${scriptdir}/01.func_correct.sh -func_in ${bold} -fdir ${fdir}"
	runfunccorrect="${runfunccorrect} -voldiscard ${voldiscard}"
	runfunccorrect="${runfunccorrect} -slicetimeinterp ${slicetimeinterp} -tmp ${tmp}"
	[[ ${despike} == "yes" ]] && runfunccorrect="${runfunccorrect} -despike"

	echo "# Generating the command:"
	echo ""
	echo "${runfunccorrect}"
	echo ""

	eval ${runfunccorrect}

done

echo "************************************"
echo "*** Func spacecomp ${task} echo 1"
echo "************************************"
echo "************************************"

echo "fmat=${fileprx}_task-${task}_${fmatsfx}"
fmat=${fileprx}_task-${task}_${fmatsfx}

${scriptdir}/03.func_spacecomp.sh -func_in ${fmat}_cr -fdir ${fdir} -anat ${anat} \
								  -mref ${sbref} -aseg ${aseg} -use_bbr -tmp ${tmp}

for e in $( seq 1 ${nTE} )
do
	echo "************************************"
	echo "*** Func realign ${task} BOLD echo ${e}"
	echo "************************************"
	echo "************************************"

	echo "bold=${fileechoprx}_echo-${e}_${fileechosfx}_cr"
	bold=${fileechoprx}_echo-${e}_${fileechosfx}_cr
	${scriptdir}/04.func_realign.sh -func_in ${bold} -fmat ${fmat} -mask ${mask} \
									-fdir ${fdir} -mref ${sbref} -tmp ${tmp}

	if [[ ${greyplot} == "yes" ]]
	then
		echo "************************************"
		echo "*** Func greyplot ${task} BOLD echo ${e} (pre)"
		echo "************************************"
		echo "************************************"
		echo "bold=${fileechoprx}_echo-${e}_${fileechosfx}_bet"
		bold=${fileechoprx}_echo-${e}_${fileechosfx}_bet
		${scriptdir}/12.func_grayplot.sh -func_in ${bold} -fdir ${fdir} -anat_in ${anat} \
										 -mref ${sbref} -aseg ${aseg} -polort 4 -tmp ${tmp}
	fi
done

echo "************************************"
echo "*** Func MEICA ${task} BOLD"
echo "************************************"
echo "************************************"

${scriptdir}/05.func_meica.sh -func_in ${fmat}_bet -fdir ${fdir} -TEs "${TEs}" -tmp ${tmp}

echo "************************************"
echo "*** Func T2smap ${task} BOLD"
echo "************************************"
echo "************************************"
# Since t2smap gives different results from tedana, prefer the former for optcom
${scriptdir}/06.func_optcom.sh -func_in ${fmat}_bet -fdir ${fdir} -TEs "${TEs}" -tmp ${tmp}

[[ ${preproc_echoes} == "yes" ]] && preproc_vols=( $( seq 1 ${nTE}) ) || preproc_vols=()
[[ ${preproc_echoes} == "second" ]] && preproc_vols=( 2 )
[[ ${preproc_optcom} == "yes" ]] && preproc_vols=( ${preproc_vols[@]} optcom )

# As it's ${task}, only skip denoising (but create matrix nonetheless)!
for e in "${preproc_vols[@]}"
do
	[[ ${e} != "optcom" ]] && e=echo-${e}

	echo "bold=${fileprx}_task-${task}_${e}_bold"
	bold=${fileprx}_task-${task}_${e}_bold
	
	echo "************************************"
	echo "*** Func Nuiscomp ${task} BOLD ${e}"
	echo "************************************"
	echo "************************************"

	runnuiscomp="${scriptdir}/07.func_nuiscomp.sh -func_in ${bold}_bet -fmat_in ${fmat}"
	runnuiscomp="${runnuiscomp} -mref ${sbref} -fdir ${fdir} -tmp ${tmp}"
	runnuiscomp="${runnuiscomp} -anat ${anat} -aseg ${aseg} -polort ${polort}"
	[[ ${den_motreg} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_motreg"
	[[ ${den_detrend} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_detrend"
	[[ ${den_meica} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_meica"
	[[ ${den_tissues} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_tissues"
	[[ ${applynuisance} == "yes" ]] && runnuiscomp="${runnuiscomp} -applynuisance" && boldsource=${bold}_den || boldsource=${bold}_bet

	echo "# Generating the command:"
	echo ""
	echo "${runnuiscomp}"
	echo ""

	eval ${runnuiscomp}
	
	echo "************************************"
	echo "*** Func Pepolar ${task} BOLD ${e}"
	echo "************************************"
	echo "************************************"

	${scriptdir}/02.func_pepolar.sh -func_in ${boldsource} -fdir ${fdir} \
									-pepolar ${sbref}_topup -tmp ${tmp}

	boldout=$( basename ${bold} )
	if [[ ${fwhm} != "none" ]]
	then

		echo "************************************"
		echo "*** Func smoothing ${task} BOLD ${e}"
		echo "************************************"
		echo "************************************"

		${scriptdir}/08.func_smooth.sh -func_in ${bold}_tpp -fdir ${fdir} -fwhm ${fwhm} -mask ${mask} -tmp ${tmp}
		boldsource=${bold}_sm
	else
		boldsource=${bold}_tpp
	fi

	echo "3dcalc -a ${boldsource}.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale"
	3dcalc -a ${boldsource}.nii.gz -b ${mask}.nii.gz -expr 'a*b' \
		   -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz \
		   -short -gscale -overwrite

	if [[ ${greyplot} == "yes" ]]
	then
		echo "************************************"
		echo "*** Func greyplot ${task} BOLD echo ${e} (post)"
		echo "************************************"
		echo "************************************"
		${scriptdir}/12.func_grayplot.sh -func_in ${boldsource} -fdir ${fdir} -anat_in ${anat} \
										 -mref ${sbref} -aseg ${aseg} -polort 4 -tmp ${tmp}
	fi
done

[[ ${debug} == "yes" ]] && set +x

exit 0