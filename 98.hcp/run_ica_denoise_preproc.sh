#$ -S /bin/bash
#$ -cwd
#$ -m be
#$ -M s.moia@bcbl.eu

module load singularity/3.3.0

##########################################################################################################################
##---START OF SCRIPT----------------------------------------------------------------------------------------------------##
##########################################################################################################################

date

wdir=/bcbl/home/public/PJMASK_2

cd ${wdir}

singularity exec -e --no-home \
			-B /bcbl/home/public/PJMASK_2/preproc:/data \
			-B /bcbl/home/public/PJMASK_2/EuskalIBUR_preproc:/scripts \
			-B /export/home/smoia/scratch:/tmp \
			/bcbl/home/public/PJMASK_2/euskalibur.sif /scripts/00.pipelines/custom/ica_denoise_preproc.sh \
						-sub $1 -ses $2 -wdr /data -prjname ica_denoise -tmp /tmp
