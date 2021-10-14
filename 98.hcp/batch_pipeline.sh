#$ -S /bin/bash
#$ -cwd
#$ -m be
#$ -M s.moia@bcbl.eu

module load singularity/3.3.0

##########################################################################################################################
##---START OF SCRIPT----------------------------------------------------------------------------------------------------##
##########################################################################################################################

date

wdr=/bcbl/home/public/PJMASK_2/EuskalIBUR_preproc

cd ${wdr}

if [[ ! -d ../LogFiles ]]
then
	mkdir ../LogFiles
fi

# Run full preproc
joblist1=""
joblist2=""

for sub in 001 002 003 004 005 006 007 008 009 010
do
	rm ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_01
	qsub -q long.q -N "cp_pp_${sub}_01" \
	-o ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_01 \
	-e ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_01 \
	${wdr}/98.hcp/run_cvr_pressure_preproc.sh ${sub} 01
	joblist1=${joblist1}cp_pp_${sub}_01,

	rm ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_01
	qsub -q long.q -N "cp_pp_${sub}_01" \
	-o ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_01 \
	-e ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_01 \
	${wdr}/98.hcp/run_ica_denoise_preproc.sh ${sub} 01
	joblist2=${joblist2}cp_pp_${sub}_01,
done

joblist1=${joblist1::-1}
joblist2=${joblist2::-1}

for sub in 001 002 003 004 005 006 007 008 009 010
do
	for ses in $(seq -f %02g 2 10)
	do
		rm ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_${ses}
		qsub -q long.q -N "cp_pp_${sub}_${ses}" \
		-hold_jid "${joblist1}" \
		-o ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_${ses} \
		-e ${wdr}/../LogFiles/cvr_pressure_preproc_${sub}_${ses} \
		${wdr}/98.hcp/run_cvr_pressure_preproc.sh ${sub} ${ses}

		rm ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_${ses}
		qsub -q long.q -N "cp_pp_${sub}_${ses}" \
		-hold_jid "${joblist2}" \
		-o ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_${ses} \
		-e ${wdr}/../LogFiles/ica_denoise_preproc_${sub}_${ses} \
		${wdr}/98.hcp/run_ica_denoise_preproc.sh ${sub} ${ses}
	done
done

rm ${wdr}/../LogFiles/cvr_pressure_preproc_010_11
qsub -q long.q -N "cp_pp_010_11" \
-hold_jid "${joblist1}" \
-o ${wdr}/../LogFiles/cvr_pressure_preproc_010_11 \
-e ${wdr}/../LogFiles/cvr_pressure_preproc_010_11 \
${wdr}/98.hcp/run_cvr_pressure_preproc.sh 010 11

rm ${wdr}/../LogFiles/ica_denoise_preproc_010_11
qsub -q long.q -N "cp_pp_010_11" \
-hold_jid "${joblist2}" \
-o ${wdr}/../LogFiles/ica_denoise_preproc_010_11 \
-e ${wdr}/../LogFiles/ica_denoise_preproc_010_11 \
${wdr}/98.hcp/run_ica_denoise_preproc.sh 010 11
