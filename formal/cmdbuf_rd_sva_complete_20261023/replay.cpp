// Replay actual SBY input witnesses against the original native SVA and SV DUT.
// DUT outputs are compared, never driven. This is trace validation, not proof.
#include "Vcmdbuf_rd.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

int main(int argc,char**argv) {
    if(argc!=3) return 2;
    auto context=std::make_unique<VerilatedContext>();context->commandArgs(argc,argv);
    auto dut=std::make_unique<Vcmdbuf_rd>(context.get());
    dut->clk=0;dut->rst_n=0;dut->eval();dut->clk=1;dut->eval();dut->clk=0;dut->eval();
    std::ifstream in(argv[1]);std::string line;unsigned cycle=0;
    try {
        if(!in)throw std::runtime_error("Cannot open trace inputs");
        while(std::getline(in,line)) {
            if(line.empty())continue;
            std::istringstream ss(line);std::string s;std::vector<uint32_t>x;
            while(ss>>s)x.push_back(std::stoul(s,nullptr,16));
            if(x.size()!=30)throw std::runtime_error("Trace row must have 30 columns");
            dut->clk=0;dut->rst_n=x[0];dut->arvalid=x[1];dut->araddr=x[2];dut->src=x[3];
            dut->arid=x[4];dut->ar_port_id=x[5];dut->arresp=x[6];dut->rready=x[7];
            dut->ar_rd_gnt=x[8];dut->rw_rd_gnt=x[9];
            for(unsigned b=0;b<8;b++)dut->rd_mem_status[b]=(x[10]>>(2*b))&3;
            for(unsigned b=0;b<4;b++)dut->mem_rdata[b]=x[11+b];
            dut->pc_err=x[15];dut->eval();
            auto check=[&](uint32_t a,uint32_t b,const char*n){
                if(a!=b){std::cerr<<"cycle="<<cycle<<" "<<n<<" actual="<<a<<" witness="<<b<<"\n";throw std::runtime_error("output mismatch");}
            };
            check(dut->arready,x[16],"arready");check(dut->req,x[17],"req");
            if(x[17])check(dut->arb_addr,x[18],"arb_addr");
            check(dut->pending_cnt,x[19],"pending_cnt");check(dut->rvalid,x[20],"rvalid");
            if(x[20]) {
                for(unsigned b=0;b<4;b++)check(dut->rdata[b],x[21+b],"rdata");
                check(dut->rid,x[25],"rid");check(dut->r_port_id,x[26],"r_port_id");
                check(dut->raddr,x[27],"raddr");check(dut->rresp,x[28],"rresp");
            }
            // Last column is the formal step number, for trace audit only.
            dut->clk=1;dut->eval();context->timeInc(1);++cycle;
        }
        dut->final();context->coveragep()->write(argv[2]);
        std::cout<<"PASS replay cycles="<<cycle<<"\n";return 0;
    } catch(const std::exception&e) {std::cerr<<e.what()<<"\n";return 1;}
}
