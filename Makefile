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

input_files := $(wildcard $(read_folder)/*.fastq.gz) $(wildcard $(read_folder)/*.fq.gz) $(wildcard $(read_folder)/*.fq) $(wildcard $(read_folder)/*.fastq)

ifneq "$(words $(input_files))" "2"
$(error Invalid number of paired-end read files in reads folder)
endif

#Run params from
ifndef cfg_file
$(error Config file variable 'cfg_file' not set)
endif
include $(cfg_file)

#Additional parameter: tax_assign_target

#Logging info
export log_name := $(CURDIR)$(sample_name)_$(shell date +%s).log
export log_file := >( tee -a $(log_name) >&2 )

#Avoid the parallel execution of rules in this makefile
.NOTPARALLEL:

.PHONY: all raw_qc qf_qc quality_filtering contamination_rm assembly tax_assign

all: raw_qc quality_filtering qf_qc contamination_rm assembly tax_assign

#QC raw reads
raw_qc: $(input_files)
	mkdir -p $@
	if [ ! -r $@/qc.mak ]; then cp steps/qc.mak $@/; fi
	cd raw_qc && $(MAKE) -rf qc.mak read_folder=../reads/ step=raw basic
	#Delete tmp
	-cd raw_qc && $(MAKE) -rf qc.mak read_folder=../reads/ step=raw clean-tmp

#Quality filtering
quality_filtering: $(input_files)
	mkdir -p $@
	if [ ! -r quality_filtering/quality_filtering.mak ]; then cp steps/quality_filtering.mak $@/; fi
	cd $@ && $(MAKE) -rf quality_filtering.mak read_folder=../reads/ STRATEGY=2_nesoni

#QC Quality filtering
qf_qc: quality_filtering
	mkdir -p $@
	if [ ! -r $@/qc.mak ]; then cp steps/qc.mak $@; fi
	cd $@ && $(MAKE) -rf qc.mak read_folder=../$^/ step=qf basic
	-cd $@ && $(MAKE) -rf qc.mak read_folder=../$^/ step=qf clean-tmp

#Contamination removal (human)
contamination_rm: quality_filtering
	mkdir -p $@
	if [ ! -r $@/contamination_rm.mak ]; then cp steps/contamination_rm.mak $@; fi
	cd $@ && $(MAKE) -rf contamination_rm.mak read_folder=../$^/ step=rmcont prev_steps=qf

#Assembly step
assembly: contamination_rm
	mkdir -p $@
	if [ ! -r $@/assembly.mak ]; then cp steps/assembly.mak $@; fi
	cd $@ && $(MAKE) -rf assembly.mak read_folder=../$^/ step=asm prev_steps=qf_rmcont

#Taxonomic / Functional Annotation
tax_assign: assembly
	mkdir -p $@
	if [ ! -r $@/tax_assign.mak ]; then cp steps/tax_assign.mak $@; fi
	cd $@ && $(MAKE) -rf tax_assign.mak read_folder=../$^/ ctg_folder=../$^/ step=tax ctg_steps=qf_rmcont_asm read_steps=qf_rmcont_asm $(tax_assign_target)
	cd $@ && $(MAKE) -rf tax_assign.mak read_folder=../$^/ ctg_folder=../$^/ step=tax ctg_steps=qf_rmcont_asm read_steps=qf_rmcont_asm clean-tmp
