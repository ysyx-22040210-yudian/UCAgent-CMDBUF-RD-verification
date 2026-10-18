# Candidate for target FormalMC; not a certification of an unexecuted version.
set here [file dirname [file normalize [info script]]]
cd $here
read_design -top cmdbuf_rd_formal -sysv -mfcu [list [file join $here native_input.sv]]
def_clk clk
prove
show_prop -summary
exit
