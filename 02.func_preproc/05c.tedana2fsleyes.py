#!/usr/bin/env python3

import json
import os
import shutil
import sys

import numpy as np

indir = sys.argv[1]

cwd = os.getcwd()

os.chdir(indir)

os.makedirs('fsleyes', exist_ok=True)

shutil.copy2('ica_components.nii.gz', os.path.join('fsleyes', 'melodic_IC.nii.gz'))

d = np.genfromtxt('ica_mixing.tsv', skip_header=1)

np.savetxt(os.path.join('fsleyes', 'melodic_mix'), d)

ps = np.abs(np.fft.rfft(d, axis=0)) ** 2

np.savetxt(os.path.join('fsleyes', 'melodic_FTmix'), ps[1:, :])

# Load JSON
with open('ica_decomposition.json', 'r') as f:
    data = json.load(f)

rows = []

# Extract ICA components
for key in data:
    if key.startswith('ica_'):
        comp_number = int(key.split('_')[1]) + 1 
        classification = data[key]['classification']
        classification = 'Signal' if classification == 'accepted' else classification
        remvar = 'True' if classification == 'rejected' else 'False'
        rows.append((comp_number, classification, remvar))

# Sort by component number
rows.sort(key=lambda x: x[0])

labeldir = os.path.join(os.getcwd(), 'fsleyes')

with open('rejected_list.1D', 'r') as f:
    rejected_line = [int(x) + 1 for x in f.readline().strip().split(',') if x]

# Write melodic_labels file
with open(os.path.join('fsleyes', 'melodic_labels'), 'w') as f:
    f.write(f'{labeldir}\n')

    for comp, label, remvar in rows:
        f.write(f'{comp},{label},{remvar}\n')

    f.write('[' + ','.join(map(str, rejected_line)) + ']\n')

os.chdir(cwd)
