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

## 01. MEICA
# 01.1. concat in space

if [[ ! -e ${tmp}/${func}.nii.gz ]];
then
	echo "Merging ${func} for MEICA"
	fslmerge -z ${tmp}/${func} $( ls ${tmp}/${eprx}* | grep ${esfx}.nii.gz )
else
	echo "Merged ${func} found!"
fi

replace_and mkdir ${tmp}/${func}_meica

echo ""
echo "---------------------------"
echo "MAKE SURE PYTHON IS CORRECT"
echo "---------------------------"
alias python=/usr/bin/python
alias python3=/usr/bin/python3
alias
echo "Python: $( which python ) $( which python3 )"
echo ""


echo ""
echo "--------------"
echo "Running tedana"
echo "--------------"
echo "Python: $( which python ) $( which python3 )"

tedana -d ${tmp}/${func}.nii.gz -e ${TEs} --tedpca mdl --out-dir ${tmp}/${func}_meica

cd ${tmp}/${func}_meica

# 01.4. Orthogonalising good and bad components

echo "Extracting good and bad copmonents"
scriptpath="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

echo ""
echo "--------------"
echo "Running post-tedana output processing"
echo "--------------"
alias python=/usr/bin/python
alias python3=/usr/bin/python3
alias
echo "Python: $( which python ) $( which python3 )"

python3 ${scriptpath}/05b.process_tedana_output.py ${tmp}/${func}_meica

echo "Orthogonalising good and bad components in ${func}"
nacc=$( cat accepted_list.1D )
nrej=$( cat rejected_list.1D )

# Store some files for data check or later use
replace_and mkdir ${fdir}/${func}_meica ${fdir}/${func}_meica/figures

cp accepted_list.1D ignored_list.1D rejected_list.1D accepted_list_by_variance.1D \
   ignored_list_by_variance.1D rejected_list_by_variance.1D ${fdir}/${func}_meica/.
cp adaptive_mask.nii.gz ica_decomposition.json ica_mixing_orig.tsv ica_mixing.tsv ${fdir}/${func}_meica/.
cp -r figures ${fdir}/${func}_meica/figures

1dcat ica_mixing.tsv"[$nacc]" > accepted.1D
1dcat ica_mixing.tsv"[$nrej]" > rej.tr.1D
1dtranspose rej.tr.1D > rejected.1D

3dTproject -ort accepted.1D -polort -1 -prefix ${tmp}/tr.1D -input rejected.1D -overwrite
1dtranspose ${tmp}/tr.1D > ${fdir}/$( basename ${func_in%_*} )_rej_ort.1D

cd ${cwd}