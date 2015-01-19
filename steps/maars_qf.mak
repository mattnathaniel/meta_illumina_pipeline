# Raw reads quality filtering pipeline
# Modified for MAARS project samples

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

#Make parameters
SHELL := /bin/bash

ifndef sample_name
$(error Variable 'sample_name' is not defined)
endif

ifndef read_folder
$(warning Variable 'read_folder' will be assumed to be "./")
read_folder := ./
endif

ifndef step
$(warning Variable 'step' has been defined as 'qf')
step:=qf
endif

ifndef STRATEGY
$(info Default quality filtering strategy is cutadapt+nesoni)
STRATEGY=2_nesoni
endif

#Outfile
OUT_PREFIX := $(sample_name)_$(step)

#Reads
R1 := $(wildcard $(read_folder)/*R1*.f*q.gz  $(read_folder)/*_1.f*q.gz)
R2 := $(wildcard $(read_folder)/*R2*.f*q.gz  $(read_folder)/*_2.f*q.gz)

ifneq ($(words $(R1) $(R2)),2)
$(error More than one R1 or R2 $(words $(R1) $(R2)))
endif

#Logging
log_name := $(CURDIR)/$(OUT_PREFIX)_$(shell date +%s).log
log_file := >( tee -a $(log_name) >&2 )

#Run params
ifndef threads
	$(error Define threads variable in make.cfg file)
endif

#Prinseq params
#out_format: fasta 1, fastq 3
#Remove duplicates (derep) : 1=exact dup, 2= 5' dup 3= 3' dup 4= rev comp exact dup
#Low complexity filters(lc_method): dust, entropy
prinseq_params:= -verbose -out_format 3 -log prinseq.log -min_len 75 -derep 1 -lc_method dust -lc_threshold 39

#SGA parameters
sga_ec_kmer := 41
sga_cov_filter := 2

#Output name generators (notice the = instead of := to set the appropriate directory)
nesoni_out_prefix = $(dir $@)$*
prinseq_out_prefix = $(dir $@)$*

#Delete produced files if step fails
.DELETE_ON_ERROR:

#Avoids the deletion of files because of gnu make behavior with implicit rules
.SECONDARY:

.PHONY: all

all: $(OUT_PREFIX)_R1.fq.gz $(OUT_PREFIX)_R2.fq.gz $(OUT_PREFIX)_single.fq.gz

$(OUT_PREFIX)_%.fq.gz: $(STRATEGY)/$(sample_name)_%.fq.gz
	ln -fs $^ $@

#*************************************************************************
#Calls to trimmers
#*************************************************************************
1_cutadapt/%_R1.fq.gz 1_cutadapt/%_R2.fq.gz 1_cutadapt/%_single.fq.gz: $(R1) $(R2)
	mkdir -p $(dir $@)
	#Remove Illumina TruSeq Barcoded Adapter from fwd pair
	$(CUTADAPT_BIN) -a AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC --overlap=5 --error-rate=0.1 -o $(TMP_DIR)/cutadapt_r1.fq.gz $< >> $(log_file)
	#Remove reverse complement of Illumina TruSeq Universal Adapter from reverse pair
	$(CUTADAPT_BIN) -a AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGTAGATCTCGGTGGTCGCCGTATCATT --overlap=5 --error-rate=0.1 -o $(TMP_DIR)/cutadapt_r2.fq.gz $(word 2,$^) >> $(log_file)
	python ../scripts/extract_small_fragments.py --raw_read_length $(READ_LEN) -o $(dir $@)/$* $(TMP_DIR)/cutadapt_r1.fq.gz $(TMP_DIR)/cutadapt_r2.fq.gz 2>> $(log_file)

#You have to specify quality is phred33 because with cutadapt clipped fragments nesoni fails to detect encoding
2_nesoni/%_R1.fq.gz 2_nesoni/%_R2.fq.gz 2_nesoni/%_singlepairs.fq.gz: 1_cutadapt/%_R1.fq.gz 1_cutadapt/%_R2.fq.gz
	mkdir -p $(dir $@)
	$(NESONI_BIN) clip --adaptor-clip no --homopolymers yes --qoffset 33 --quality 20 --length 75 \
		--out-separate yes $(nesoni_out_prefix) pairs: $^ 2>> $(log_file)
	mv 2_nesoni/$*_single.fq.gz 2_nesoni/$*_singlepairs.fq.gz

2_nesoni/%_single.fq.gz: 1_cutadapt/%_single.fq.gz 2_nesoni/%_singlepairs.fq.gz
	mkdir -p $(dir $@)
	$(NESONI_BIN) clip --adaptor-clip no --homopolymers yes --qoffset 33 --quality 20 --length 75 \
		$(TMP_DIR)/fragments reads: $< 2>> $(log_file)
	cat $(word 2,$^) $(TMP_DIR)/fragments_single.fq.gz > $@
	-rm $(TMP_DIR)/fragments_single.fq.gz

.PHONY: clean
clean:
	-rm *.fq.gz
	-rm *.log #Makefile log
	-rm *.log.txt #Nesoni log
