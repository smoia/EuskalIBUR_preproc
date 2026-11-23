Data preprocessing for EuskalIBUR
=================================

This library is meant to run the data preprocessing on the dataset *EuskalIBUR* (currently available on request).
It is meant to run in the included Apptainer container (easier on Linux systems, see [here](https://apptainer.org/docs/admin/main/installation.html):
```bash
apptainer build -f ../containers/EuskalIBUR_preproc.sif EuskalIBUR_preproc.def
apptainer exec -e --no-home -B {{ path to scripts }}:/scripts EuskalIBUR_preproc.sif /scripts/00.pipelines/00.full_preproc.sh -h
```

Warning
-------
Run the container with virtual screens to run scripts that create figures (i.e. those using fsleyes or interactive matplotlib sessions)
