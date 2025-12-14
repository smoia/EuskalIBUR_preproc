#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

# Check if there is input
[[ ( $# -eq 0 ) ]] && displayhelp $0 1

# Preparing the default values for variables
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
		-TEs)		TEs="$2";shift;;

		-tmp)		tmp=$2;shift;;

		-h)			displayhelp $0;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp $0 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir TEs
checkoptvar tmp

### Remove nifti suffix
func_in=${func_in%.nii*}

### Cath errors and exit on them
set -e
######################################
######### Script starts here #########
######################################
echo ""
echo "Make sure system python is used by prepending /usr/bin to PATH"
[[ "${PATH%%:*}" != "/usr/bin" ]] && export PATH=/usr/bin:$PATH
echo "PATH is set to $PATH"
echo ""

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
esfx=$( basename ${func_in#*_echo-?} )
eprx=$( basename ${func_in%_echo-*}_echo- )
func=$( basename ${func_in%_echo-*}_concat${esfx} )
func_optcom=$( basename ${func_in%_echo-*}_optcom${esfx} )

## 01. MEICA
# 01.1. concat in space

if [[ ! -e ${tmp}/${func}.nii.gz ]];
then
	echo "Merging ${func} for MEICA"
	fslmerge -z ${tmp}/${func} $( ls ${tmp}/${eprx}* | grep ${esfx}.nii.gz )
else
	echo "Merged ${func} found!"
fi

if [[ ! -e ${tmp}/${func_optcom} ]]
then
	echo "Running t2smap"
	cd ${tmp} || exit
	echo ""
	echo "--------------"
	echo "Running t2smap"
	echo "--------------"
	alias python=/usr/bin/python
	alias python3=/usr/bin/python3
	alias
	echo "Python: $( which python ) $( which python3 )"

	t2smap -d ${tmp}/${func}.nii.gz -e ${TEs}

	echo "Housekeeping"
	fslmaths TED.${func}/ts_OC.nii.gz ${tmp}/${func_optcom} -odt float
	cd ${fdir} || exit
fi

# 01.3. Compute outlier fraction if there's more than one TR
nTR=$(fslval ${tmp}/${func_optcom} dim4)

if [[ "${nTR}" -gt "1" ]]
then
	echo "Computing outlier fraction in ${func_optcom}"
	fslmaths ${tmp}/${func_optcom} -Tmean ${tmp}/${func_optcom}_avg
	brain_extract -nii ${tmp}/${func_optcom}_avg -method fsss -tmp ${tmp} -nobrain

	3dToutcount -mask ${tmp}/${func_optcom}_avg_brain_mask.nii.gz -fraction -polort 5 -legendre ${tmp}/${func_optcom}.nii.gz > ${func_optcom%_bet}_outcount.1D
	rm -rf ${tmp}/${func_optcom}_avg*
fi

cd ${cwd}
