#!/bin/sh

set -xe

rdmd -g -L-lLLVM-8 -version=LLVM_8_0_0 -verrors=context -checkaction=context workaround.o src/lexer.d
echo "\n\n\n"
llc-8 -relocation-model=pic -filetype=obj mmm.bc 
gcc mmm.o -o mmm
llvm-dis-8 mmm.bc
./mmm 
echo "\n\n\n"