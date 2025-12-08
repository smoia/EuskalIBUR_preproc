#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
argsbet="-R -f 0.5 -g 0 -n -m"
args3dss="-orig_vol -overwrite"
args3dam=""
argsfsss=""
exportbrain=yes
exportallmasks=no
tmp=.
debug=no

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-nii)		nii=$2;shift;;								# Nifti file(s) to be brainmasked. Output will be in the same folder, with _brain_mask and _brain as suffix. Input for avgbet must be 4D.
		-method)	IFS=" " read -r -a method <<< $2;shift;;	# Method to use for brain extraction. Available: bet, avgbet, 3dSkullStrip (3dss), 3dAutomask (3dam), synthstrip (fsss). Multiple options available "".

		-argsbet)	argsbet="$2";shift;;	# Arguments for FSL's bet (including avgbet). Must be within "".
		-args3dss)	args3dss="$2";shift;;	# Arguments for AFNI's 3dSkullStrip. Must be within "".
		-args3dam)	args3dam="$2";shift;;	# Arguments for AFNI's 3dAutomask. Must be within "".
		-argsfsss)	argsfsss="$2";shift;;	# Arguments for FS's synthstrip. Must be within "".
		-nobrain)	exportbrain=no;;		# Do not export the brain image, produce the mask only.
		-allmasks)	exportallmasks=yes;;	# Export all masks if multiple methods were defined.

		-tmp)		tmp=$2;shift;;				# Folder for temporary files. If not in debug mode, it'll be deleted at the end.
		-debug)		debug=yes;;					# Turn on debug mode.

		-h)			displayhelp $0;;			# Display help.
		-v)			version;exit 0;;			# Display version.
		*)			echo "Wrong flag: $1";displayhelp $0 1;; # Anything else is wrong!
	esac
	shift
done

# Check input
checkreqvar nii method
checkoptvar argsbet args3dss args3dam exportbrain tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
nii=$( removeniisfx ${nii} )

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

niiname=$( basename ${nii} )
ndir=$( dirname $( realpath ${nii} ) )
tmp=${tmp}/${niiname}_brainmask

replace_and mkdir ${tmp}

for m in "${method[@]}"
do
	case ${m} in
		bet)
			echo "Extracting brain with FSL's BET"
			echo "bet ${nii} ${tmp}/${niiname}_bet_brain ${argsbet}"
			eval "bet ${nii} ${tmp}/${niiname}_bet_brain ${argsbet}"
			mask=${tmp}/${niiname}_bet_brain_mask;;
		avgbet)
			echo "Extracting brain with FSL's BET on temporally averaged input files"
			fslmaths ${nii} -Tmean ${tmp}/${niiname}_avg
			echo "bet ${tmp}/${niiname}_avg ${tmp}/${niiname}_avgbet_brain ${argsbet}"
			eval "bet ${tmp}/${niiname}_avg ${tmp}/${niiname}_avgbet_brain ${argsbet}"
			mask=${tmp}/${niiname}_avgbet_brain_mask;;
		3dSkullStrip|3dss) 
			echo "Extracting brain with AFNI's 3dSkullStrip"
			echo "3dSkullStrip -input ${nii}.nii.gz -prefix ${tmp}/${niiname}_3dss_brain.nii.gz ${args3dss}"
			eval "3dSkullStrip -input ${nii}.nii.gz -prefix ${tmp}/${niiname}_3dss_brain.nii.gz ${args3dss}"
			# Momentarily forcefully change header because SkullStrips plumbs the volume.
			3dcalc -a ${nii}.nii.gz -b ${tmp}/${niiname}_3dss_brain.nii.gz -expr "astep(a*astep(b,0),0)" \
				   -prefix ${tmp}/${niiname}_3dss_brain_mask.nii.gz -overwrite
			mask=${tmp}/${niiname}_3dss_brain_mask;;
		3dAutomask|3dam)
			echo "Extracting brain with AFNI's 3dAutomask"
			echo "3dAutomask -prefix ${tmp}/${niiname}_3dam_brain_mask.nii.gz ${args3dam} ${nii}.nii.gz"
			eval "3dAutomask -prefix ${tmp}/${niiname}_3dam_brain_mask.nii.gz ${args3dam} ${nii}.nii.gz"
			mask=${tmp}/${niiname}_3dam_brain_mask;;
		synthstrip|fsss)
			echo "Extracting brain with Fresurfer's SynthStrip"
			[[ -d ${FREESURFER_HOME}/ssenv ]] && source ${FREESURFER_HOME}/ssenv/bin/activate
			echo "mri_synthstrip -i ${nii}.nii.gz -o ${tmp}/${niiname}_fsss_brain.nii.gz -m ${tmp}/${niiname}_fsss_brain_mask.nii.gz ${argsfsss}"
			eval "mri_synthstrip -i ${nii}.nii.gz -o ${tmp}/${niiname}_fsss_brain.nii.gz -m ${tmp}/${niiname}_fsss_brain_mask.nii.gz ${argsfsss}"
			[[ -d ${FREESURFER_HOME}/ssenv ]] && deactivate
			mask=${tmp}/${niiname}_fsss_brain_mask;;

		*)	echo "Option ${m} not supported yet." && exit 1;;
	esac
done

if [[ ${#method[@]} -gt 1 ]]
then
	echo "Merging multiple masks together"
	fslmerge -t ${tmp}/${niiname}_merge_brain_mask ${tmp}/${niiname}_*_brain_mask.nii.gz
	fslmaths ${tmp}/${niiname}_merge_brain_mask -Tmax -bin ${ndir}/${niiname}_brain_mask
	if [[ ${exportallmasks} == "yes" ]]
	then
		for mask in ${tmp}/${niiname}_*_brain_mask.nii.gz
		do
			maskmethod=${mask%_brain_mask.nii.gz}
			maskmethod=${maskmethod##*_}
			mv ${mask} ${ndir}/${niiname}_brain_mask_${maskmethod}
		done
	fi
else
	mv ${mask}.nii.gz ${ndir}/${niiname}_brain_mask.nii.gz
fi

if [[ ${exportbrain} == "yes" ]]
then
	if ! command -v fslmaths &>/dev/null
	then
		if [[ ${#method[@]} -eq 1 ]] && [[ "${method[0]}" == "fsss" || "${method[0]}" == "synthstrip" ]]
		then
			mv ${mask%_mask}.nii.gz ${ndir}/${niiname}_brain.nii.gz
		else
				3dcalc -a ${nii}.nii.gz -b ${ndir}/${niiname}_brain_mask.nii.gz -expr "a*astep(b,0)" \
					   -prefix ${ndir}/${niiname}_brain.nii.gz -overwrite
		fi
	else
		fslmaths ${nii} -mas ${ndir}/${niiname}_brain_mask.nii.gz ${ndir}/${niiname}_brain.nii.gz
	fi
fi


cd ${cwd}

if [[ ${debug} == "yes" ]]; then set +x; else rm -rf ${tmp}; fi