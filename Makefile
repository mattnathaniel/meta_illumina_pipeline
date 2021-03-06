# Viral discovery pipeline for Illumina (MiSeq) data

# Author: Mauricio Barrientos-Somarribas
# Email:  mauricio.barrientos@ki.se

# Copyright 2014 Mauricio Barrientos-Somarribas
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SHELL := /bin/bash

#Required variables

ifndef sample_name
$(error Variable sample_name not set.)
endif

export sample_name

ifndef read_folder
read_folder := reads/
$(warning 'Read folder is assumed to be $(read_folder)')
endif

#Run params from
ifndef cfg_file
$(error Config file variable 'cfg_file' not set)
endif
include $(cfg_file)

#Logging
log_name = $(sample_name)_$@_$(shell date +%s).log
log_file = >(tee -a $(log_name) >&2)

.PHONY: all raw_qc qf_qc quality_filtering contamination_rm assembly tax_assign metaphlan

all: raw_qc quality_filtering qf_qc contamination_rm assembly tax_assign metaphlan

#QC raw reads
raw_qc: $(read_folder)
	mkdir -p $@
	cd raw_qc && $(MAKE) -rf ../steps/qc.mak read_folder=../reads/ step=raw basic &>> $(log_file)
	-cd raw_qc && $(MAKE) -rf ../steps/qc.mak read_folder=../reads/ step=raw clean-tmp

#Quality filtering
quality_filtering: $(read_folder)
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/quality_filtering.mak read_folder=../reads/ &>> $(log_file)

#QC Quality filtering
qf_qc: quality_filtering
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/qc.mak read_folder=../$^/ step=qf basic &>> $(log_file)
	-cd $@ && $(MAKE) -rf ../steps/qc.mak read_folder=../$^/ step=qf clean-tmp

#Contamination removal (human)
contamination_rm: quality_filtering
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/contamination_rm.mak read_folder=../$^/ step=rmcont prev_steps=qf &>> $(log_file)

#Assembly step
assembly: contamination_rm
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/assembly.mak read_folder=../$^/ step=asm prev_steps=qf_rmcont &>> $(log_file)

#Taxonomic / Functional Annotation
tax_assign: assembly
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/tax_assign.mak read_folder=../$^/ ctg_folder=../$^/ step=tax ctg_steps=qf_rmcont_asm read_steps=qf_rmcont_asm $(tax_assign_target) &>> $(log_file)
	-cd $@ && $(MAKE) -rf ../steps/tax_assign.mak read_folder=../$^/ ctg_folder=../$^/ step=tax ctg_steps=qf_rmcont_asm read_steps=qf_rmcont_asm clean-tmp

metaphlan:
	mkdir -p $@
	cd $@ && $(MAKE) -rf ../steps/metaphlan.mak read_folder=../reads/ raw &>> $(log_file)
