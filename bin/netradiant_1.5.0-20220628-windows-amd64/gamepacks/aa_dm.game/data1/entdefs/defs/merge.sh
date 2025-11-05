#!/bin/bash

rm ../*.def

for f in *.def;
	do
	cat $f >> ../entities.def;
	echo -e "\r" >> ../entities.def;
	done
grep -v "model=" ../entities.def | grep -v "MODEL" >> ../nomodels.def
cp ../entities.def ../../entities.def

