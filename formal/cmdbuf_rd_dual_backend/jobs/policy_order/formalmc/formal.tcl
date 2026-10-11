# Generated portable FormalMC input. No reset abstraction: reset is in the model.
set here [file dirname [file normalize [info script]]]
read_design -top cmdbuf_rd_formal -sysv -mfcu [list [file join $here model.sv]]
def_clk clk
if {[info exists ::env(CMDBUF_FORMALMC_TIME)]} {
    set_opt -time $::env(CMDBUF_FORMALMC_TIME)
} else {
    set_opt -time 100000
}
prove
show_prop -summary
fanin -cover -list -dump
exit
