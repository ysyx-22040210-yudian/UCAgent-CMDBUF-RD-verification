// Stimulus uses only the 24 public ports. Checker reports real assertion/cover events.
#include "Vcmdbuf_rd_formal.h"
#include "verilated.h"
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
struct Driver {
  VerilatedContext ctx; Vcmdbuf_rd_formal dut{&ctx}; std::mt19937 rng;
  unsigned cycle=0, accepted=0, returned=0, issued=0; bool strict=false; std::ofstream trace;
  Driver(unsigned seed,const char* path):rng(seed),trace(path) {
    dut.clk=0;dut.rst_n=0;dut.arvalid=0;dut.src=0;dut.araddr=0;
    dut.arid=0;dut.ar_port_id=0;dut.arresp=0;dut.rready=0;
    dut.rd_mem_status=0;dut.ar_rd_gnt=0;dut.rw_rd_gnt=0;dut.pc_err=0;
    for(int i=0;i<4;i++)dut.mem_rdata[i]=0;
    tick();dut.rst_n=1;
  }
  unsigned rnd(){return rng();}
  void payload() {
    dut.arid=(cycle%7==0)?0:(rnd()&255);dut.ar_port_id=rnd()&31;
    dut.arresp=(rnd()%3==0)?3:0;dut.pc_err=(0x16>>(5-cycle%6))&1;
    for(int i=0;i<4;i++)dut.mem_rdata[i]=rnd();
  }
  void tick() {
    dut.clk=0;dut.eval();
    if(dut.arready==0){if(strict && dut.arvalid){std::cerr<<"REPLAY_INPUT_CONTRACT_FAIL\n";std::exit(5);}dut.arvalid=0;}
    dut.eval();
    if(dut.rst_n) {
      accepted+=dut.arvalid && ((dut.arready>>dut.src)&1);
      returned+=bool(dut.rvalid&dut.rready);
      issued+=bool(dut.req&dut.ar_rd_gnt&dut.rw_rd_gnt);
    }
    trace<<cycle<<' '<<unsigned(dut.rst_n)<<' '<<unsigned(dut.arvalid)<<' '<<unsigned(dut.src)<<' '<<dut.araddr<<' '
      <<unsigned(dut.arid)<<' '<<unsigned(dut.ar_port_id)<<' '<<unsigned(dut.arresp)<<' '<<unsigned(dut.rready)<<' '
      <<dut.rd_mem_status<<' '<<unsigned(dut.ar_rd_gnt)<<' '<<unsigned(dut.rw_rd_gnt)<<' '<<unsigned(dut.pc_err);
    for(int i=0;i<4;i++)trace<<' '<<dut.mem_rdata[i];trace<<'\n';
    ctx.timeInc(1);dut.clk=1;dut.eval();ctx.timeInc(1);dut.clk=0;dut.eval();cycle++;
  }
  void step(bool offer,int src,int addr,int busy=0,int ready=7,int ga=255,int gw=255) {
    payload();dut.arvalid=offer;dut.src=src;dut.araddr=addr;dut.rd_mem_status=busy;
    dut.rready=ready;dut.ar_rd_gnt=ga;dut.rw_rd_gnt=gw;tick();
  }
  void drain(int n=40){for(int i=0;i<n;i++)step(false,0,rnd()&0x3ffff);}
};
int main(int argc,char**argv){
  if(argc<4)return 2;std::string mode=argv[1];int arg=std::atoi(argv[2]);Driver d(arg+123,argv[3]);
  if(mode=="replay"){
    if(argc<5)return 2;std::ifstream f(argv[4]);uint64_t v[17];d.strict=true;
    while(f>>v[0]){
      for(int i=1;i<17;i++)if(!(f>>v[i]))return 6;
      if(v[0]==0)continue;if(v[0]!=d.cycle)return 7;
      d.dut.rst_n=v[1];d.dut.arvalid=v[2];d.dut.src=v[3];d.dut.araddr=v[4];
      d.dut.arid=v[5];d.dut.ar_port_id=v[6];d.dut.arresp=v[7];d.dut.rready=v[8];
      d.dut.rd_mem_status=v[9];d.dut.ar_rd_gnt=v[10];d.dut.rw_rd_gnt=v[11];d.dut.pc_err=v[12];
      for(int i=0;i<4;i++)d.dut.mem_rdata[i]=v[13+i];d.tick();
    }
  } else if(mode=="isolated"){
    int s=arg/16,t=arg%16;d.step(true,s,(t<<3)|7);d.drain(15);
  } else if(mode=="occupancy"){
    int occ[3]={arg/100,(arg/10)%10,arg%10};
    for(int s=0;s<3;s++)for(int i=0;i<occ[s];i++)d.step(true,s,(i<<3)|s,65535,0);
    d.step(false,0,0,65535,0);d.drain();
  } else if(mode=="busy6"){
    for(int i=0;i<5;i++)d.step(true,0,0,1,0);
    d.step(true,1,8,1,0);for(int i=0;i<24;i++)d.step(false,2,0,1,0);
    d.drain();for(int i=0;i<3;i++)d.step(true,2,16+i*8);d.drain();
  } else if(mode=="retry"){
    d.step(true,0,0,0,0);int failure=0;
    for(int i=0;i<40;i++){
      d.dut.clk=0;d.dut.eval();bool req=d.dut.req;
      int ga=255,gw=255,busy=0;
      if(failure==1 && i<6)busy=1;
      if(req && failure<4){int a[]={0,255,0,2},w[]={0,0,255,2};ga=a[failure];gw=w[failure];failure++;}
      d.step(false,0,0,busy,i>25?7:0,ga,gw);
    }d.drain();
  } else if(mode=="burst"){
    for(int i=0;i<arg;i++)d.step(true,i%3,i*8,65535,0);
    d.drain(45);d.step(true,1,123);d.drain();
  } else if(mode=="backlog"){
    for(int i=0;i<9;i++)d.step(true,i%3,i*8,0,0);
    for(int i=0;i<12;i++)d.step(false,0,0,0,0);
    if(arg==1)for(int m=0;m<8;m++)d.step(false,0,0,0,m);
    else if(arg>=2){d.step(false,0,0,0,arg%8);d.step(false,0,0,0,(arg/8)%8);}
    d.drain();
  } else if(mode=="outorder"){
    d.step(true,0,0,1,0);d.step(true,0,8,1,0);
    for(int i=0;i<12;i++)d.step(false,0,0,1,7);d.drain();
  } else if(mode=="window_return"){
    d.step(true,0,8,1,7);
    for(int i=0;i<5;i++)d.step(true,0,0,1,7,i==1?0:255,255);
    d.step(true,1,16,1,7);for(int i=0;i<10;i++)d.step(false,0,0,1,7);d.drain();
  } else if(mode=="sixth"){
    for(int i=0;i<9;i++)d.step(true,i%3,i*8,65535,0);
    for(int i=0;i<10;i++)d.step(false,0,0,65535^1^32,0);d.drain();
  } else if(mode=="fullrate"){
    int heavy=arg/3,target=arg%3;
    for(int i=0;i<7;i++)d.step(true,heavy,i*8,65535,0);
    for(int s=0;s<3;s++)if(s!=heavy)d.step(true,s,64+s*8,65535,0);
    for(int i=0;i<18;i++)d.step(false,0,0,0,0);
    for(int i=0;i<25;i++){
      d.payload();d.dut.rready=(i==0)?(1<<heavy):7;d.dut.eval();
      int pick=target;for(int j=0;j<3;j++)if((d.dut.arready>>((target+j)%3))&1){pick=(target+j)%3;break;}
      d.dut.arvalid=1;d.dut.src=pick;d.dut.araddr=(i*137)^7;
      d.dut.arid=(~d.dut.rid)&255;d.dut.ar_port_id=(~d.dut.r_port_id)&31;
      d.dut.araddr=(d.dut.araddr&~7)|((~d.dut.raddr)&7);d.tick();
    }d.drain();
  } else if(mode=="longflow"){
    for(int i=0;i<4100;i++)d.step(true,i%3,(i*83)&0x3ffff);d.drain();
  } else if(mode=="hotspot"){
    for(int i=0;i<9;i++)d.step(true,i%3,(i%2)*64,0,0,0,0);
    for(int i=0;i<20;i++)d.step(false,0,0,(i%2)?256:1,0);
    d.drain();
  } else if(mode=="idle"){
    for(int i=0;i<70;i++)d.step(false,0,0);d.step(true,0,0);d.drain();
  } else if(mode=="walking"){
    for(int k=0;k<600;k++){
      d.payload();d.dut.arvalid=1;d.dut.src=k%3;d.dut.araddr=(k%16)*8;
      d.dut.rready=7;d.dut.rd_mem_status=0;d.dut.ar_rd_gnt=255;d.dut.rw_rd_gnt=255;
      int b=k%128;bool inv=(k/128)%2;
      for(int w=0;w<4;w++)d.dut.mem_rdata[w]=inv?0xffffffff:0;
      if(inv)d.dut.mem_rdata[b/32]&=~(1u<<(b%32));else d.dut.mem_rdata[b/32]|=(1u<<(b%32));
      if(k>=540)for(int w=0;w<4;w++)d.dut.mem_rdata[w]=(k&1)?0xffffffff:0;
      d.tick();
    }d.drain();
  } else if(mode=="perf"){
    for(int i=0;i<540;i++)d.step(true,arg<3?arg:i%3,(i*83)&0x3ffff);d.drain();
  } else if(mode=="random"){
    for(int i=0;i<60000;i++){
      int phase=i%250;int busy,ready,ga,gw;
      if(phase<35){busy=65535;ready=0;ga=gw=0;}
      else if(phase<65){busy=0;ready=0;ga=gw=255;}
      else if(phase<85){busy=0;ready=7;ga=gw=255;}
      else {busy=d.rnd()&65535;ready=d.rnd()&7;ga=d.rnd()&255;gw=d.rnd()&255;}
      int addr=d.rnd()&0x3ffff;if(i%23==0)addr=0;if(i%29==0)addr=0x3ffff;
      d.step(d.rnd()%8!=0,d.rnd()%3,addr,busy,ready,ga,gw);
    }d.drain();
  }else return 3;
  std::cout<<"RUN_PASS "<<mode<<" "<<arg<<" cycles="<<d.cycle<<" accepted="<<d.accepted<<" issued="<<d.issued<<" returned="<<d.returned<<"\n";
  return d.accepted==d.returned?0:4;
}
