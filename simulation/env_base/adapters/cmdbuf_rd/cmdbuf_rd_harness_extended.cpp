#include "Vcmdbuf_rd.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using Words = std::array<uint32_t,4>;
struct Request { uint32_t addr=0; unsigned src=0,id=0,port=0,resp=0; bool parity=false,zero=false; };
struct Command { uint64_t seq=0,accepted=0; Request r; bool issued=false,done=false,failed=false; Words data{}; };
struct Stim { uint16_t status=0; unsigned argrant=255,rwgrant=255,ready=7; bool valid=false; Request request; };
struct Config { std::string type="pipeline"; unsigned seed=1,cycles=40; bool trace=false; std::map<std::string,uint64_t> required; };
static std::string trim(std::string s) { auto a=s.find_first_not_of(" \t\r\n"); if(a==std::string::npos)return ""; return s.substr(a,s.find_last_not_of(" \t\r\n")-a+1); }
static std::string escape(const std::string&s) { std::string o; for(char c:s){if(c=='"'||c=='\\')o+='\\'; if(c=='\n')o+="\\n"; else if(c=='\r')o+="\\r"; else o+=c;} return o; }
static Config read_config(const std::string& path) {
    Config cfg; std::ifstream f(path); if(!f)throw std::invalid_argument("cannot open case "+path);
    std::string line; while(std::getline(f,line)) { line=trim(line.substr(0,line.find('#'))); if(line.empty())continue; auto p=line.find('='); if(p==std::string::npos)throw std::invalid_argument("bad case line "+line);
      auto k=trim(line.substr(0,p)),v=trim(line.substr(p+1));
      if(k=="type")cfg.type=v; else if(k=="seed")cfg.seed=std::stoul(v); else if(k=="cycles")cfg.cycles=std::stoul(v); else if(k=="trace")cfg.trace=(v=="1");
      else if(k=="require"){std::stringstream ss(v); std::string item;while(std::getline(ss,item,',')){auto q=item.find(':');cfg.required[trim(item.substr(0,q))]=q==std::string::npos?1:std::stoull(item.substr(q+1));}}
      else throw std::invalid_argument("unknown case key "+k);
    } return cfg;
}
class Bench {
  public:
    Config cfg; uint64_t cycle=0,seq_next=0,checks=0; unsigned rr=0,sent=0;
    std::map<std::string,uint64_t> cov; std::vector<Command> cmds; std::map<uint64_t,uint64_t> returns;
    int64_t issue=-1; std::map<std::string,int64_t> last;
    std::unique_ptr<VerilatedContext> context; std::unique_ptr<Vcmdbuf_rd> dut; std::unique_ptr<VerilatedVcdC> trace;
    std::mt19937 rng;
    explicit Bench(Config c,const std::string& wave):cfg(c),rng(c.seed) {
      context=std::make_unique<VerilatedContext>(); context->traceEverOn(true);
      dut=std::make_unique<Vcmdbuf_rd>(context.get()); trace=std::make_unique<VerilatedVcdC>(); dut->trace(trace.get(),3); trace->open(wave.c_str());
      dut->clk=0;dut->rst_n=0;dut->arvalid=0;dut->araddr=0;dut->src=0;dut->arid=0;dut->ar_port_id=0;dut->arresp=0;dut->rready=0;dut->ar_rd_gnt=0;dut->rw_rd_gnt=0;dut->rd_mem_status=0;dut->pc_err=0;for(int i=0;i<4;i++)dut->mem_rdata[i]=0;
    }
    ~Bench(){dut->final();trace->close();}
    void eval_dump(){dut->eval();trace->dump(context->time());context->timeInc(1);}
    void check(bool ok,const std::string& why){++checks;if(!ok)throw std::runtime_error("cycle "+std::to_string(cycle)+": "+why);}
    void equal(uint64_t got,uint64_t want,const std::string& name){std::ostringstream x;x<<name<<" got=0x"<<std::hex<<got<<" expected=0x"<<want;check(got==want,x.str());}
    Command& get(uint64_t s){auto it=std::find_if(cmds.begin(),cmds.end(),[&](const auto& c){return c.seq==s;});if(it==cmds.end())throw std::runtime_error("oracle missing sequence "+std::to_string(s));return *it;}
    static unsigned bank(const Request&r){return (r.addr>>3)&7;}
    static unsigned half(const Request&r){return (r.addr>>6)&1;}
    static bool idle(const Request&r,uint16_t status){return !(status&(1u<<(half(r)*8+bank(r))));}
    static Words pattern(uint64_t s,const Request&r){if(r.zero)return {}; uint32_t a=uint32_t(s);return {0x81000000u^(a*0x9e3779b9u)^r.addr,0x1234abcdU^(a*0x7f4a7c15u),0xfedc9876u^uint32_t(r.id<<16)^uint32_t(r.src<<4),0x55aa00ffu^(a*0x6c8e9cf5u)^uint32_t(r.port)};}
    std::array<unsigned,3> occupancy()const{std::array<unsigned,3> o{};for(auto&c:cmds)o[c.r.src]++;return o;}
    void event(const std::string& k){++cov[k];if(last.count(k)&&last[k]==int64_t(cycle)-1)++cov[k+"_back_to_back"];last[k]=cycle;}
    void reset() {
      check(cmds.empty()&&returns.empty()&&issue<0,"reset scenario must be drained");
      dut->rst_n=0;dut->clk=0;dut->arvalid=0;dut->rready=0;dut->ar_rd_gnt=0;dut->rw_rd_gnt=0;
      for(int n=0;n<3;n++){dut->clk=0;eval_dump();dut->clk=1;eval_dump();equal(dut->req,0,"req during reset");equal(dut->rvalid,0,"rvalid during reset");equal(dut->arready,0,"arready during reset");equal(dut->pending_cnt,0,"pending during reset");}
      dut->clk=0;dut->rst_n=1;eval_dump();rr=0;issue=-1;returns.clear();sent=0;++cov["reset"];
    }
    Request request(unsigned n,unsigned source,unsigned b)const {
      Request r; r.src=source;r.id=(0xa5u-29u*n)&255;r.port=(19u+7u*n)&31;
      r.addr=((0x480u+n)&0xfff)<<6; r.addr=(r.addr&~0x7fu)|((n&1)<<6)|((b&7)<<3)|(n&7);
      r.addr&=0x3ffff;return r;
    }
    Stim drive(unsigned local,bool draining=false) {
      Stim s;if(draining)return s;
      auto offer=[&](Request r){s.valid=true;s.request=r;};
      auto normal=[&](unsigned total){if(sent<total)offer(request(sent,sent%3,sent%8));};
      if(cfg.type=="pipeline"||cfg.type=="throughput"){if(sent<(cfg.type=="throughput"?cfg.cycles:24))offer(request(sent,0,sent%8));}
      else if(cfg.type=="same_xau_ooo"){s.status=local<10?0x0101:0;if(sent<6)offer(request(sent,0,sent?1+(sent%6):0));}
      else if(cfg.type=="window_block"){s.status=local<18?0x0101:0;if(sent<6)offer(request(sent,0,sent<5?0:1));}
      else if(cfg.type=="failure_5a"){if(sent<8)offer(request(sent,sent%3,sent%8));if(local==2)s.rwgrant=0;}
      else if(cfg.type=="forward_6b"){s.status=local<8?0x0303:(local<14?0x0202:0);if(sent<6)offer(request(sent,0,sent==0?0:(sent<5?1:2)));}
      else if(cfg.type=="grants"){normal(24);unsigned mode=local%9;unsigned b=issue<0?0:bank(get(issue).r);if(mode==2)s.rwgrant=0;else if(mode==3)s.argrant=0;else if(mode==4){s.argrant=s.rwgrant=1u<<((b+1)%8);}else if(mode==5)s.argrant=s.rwgrant=0;}
      else if(cfg.type=="single_pulse"){s.ready=local<22?0:7;if(sent<7){auto r=request(sent,0,sent%8);r.zero=sent==0;r.parity=sent==1;offer(r);}}
      else if(cfg.type=="errors"){if(sent<4){auto r=request(sent,sent%3,sent);r.resp=(sent&2)?3:0;r.parity=(sent&1);offer(r);}}
      else if(cfg.type=="rr"){s.ready=local<22?0:7;normal(9);}
      else if(cfg.type=="rr_masks"){s.ready=local<12?0:(local==12?6:(local==13?1:(local==14?0:(local==15?4:7))));normal(3);}
      else if(cfg.type=="capacity_700"){s.ready=local<24?0:7;if(sent<7)offer(request(sent,0,sent%8));else if(sent==7)offer(request(sent,local<12?0:1,sent%8));else if(sent==8)offer(request(sent,2,sent%8));}
      else if(cfg.type=="capacity_440"){s.ready=local<24?0:7;if(sent<8)offer(request(sent,sent%2,sent%8));else if(sent==8)offer(request(sent,local<13?0:2,sent%8));}
      else if(cfg.type=="capacity_reuse"){s.ready=local<20?0:(local==20?2:(local==21?1:(local<26?0:7)));
        if(sent<9)offer(request(sent,sent<7?0:sent-6,sent%8));
        else if(local==20)offer(request(sent,1,3));else if(local==21)offer(request(sent,2,4));}
      else if(cfg.type=="tokens"){if(sent<8&&(local%4==0)){auto r=request(sent,sent%3,sent%8);r.zero=sent==0;offer(r);}if(local%11==6)s.rwgrant=0;}
      else if(cfg.type=="reset_clean"){normal(12);}
      else if(cfg.type=="half_sweep"){if(!cmds.empty()){const auto&r=cmds.front().r;s.status=uint16_t(~(1u<<(half(r)*8+bank(r))));}else if(sent<16){auto r=request(sent,sent%3,sent%8);r.addr=(r.addr&~64u)|((sent/8)<<6);s.status=uint16_t(~(1u<<(half(r)*8+bank(r))));offer(r);}else s.status=0xffff;}
      else if(cfg.type=="repeated_ids"){s.ready=local<30?0:7;s.status=local<10?0x0101:0;if(sent<9){auto r=request(sent,sent%3,sent%8);r.id=0x5a;offer(r);}}
      else if(cfg.type=="status_flip"){if(sent<3)offer(request(sent,sent%3,sent));s.status=local==2?0x0101:(local==3?0x0202:0);}
      else if(cfg.type=="random"){s.status=uint16_t(rng()&rng());s.ready=rng()%8;if((rng()%10)<8){auto r=request(unsigned(seq_next),rng()%3,rng()%8);r.resp=(rng()%11==0)?3:0;r.parity=(rng()%7==0);r.zero=(rng()%17==0);offer(r);}s.argrant=(rng()%5)?255:0;s.rwgrant=(rng()%4)?255:0;if(rng()%13==0){unsigned b=issue<0?0:bank(get(issue).r);s.argrant=s.rwgrant=1u<<((b+1)%8);}}
      else throw std::invalid_argument("unknown type "+cfg.type);
      return s;
    }
    void step(Stim s) {
      const auto occ=occupancy();
      std::array<int64_t,3> head{-1,-1,-1};for(const auto&c:cmds)if(head[c.r.src]<0)head[c.r.src]=c.seq;
      unsigned candidates=0;for(unsigned x=0;x<3;x++)if(head[x]>=0&&get(head[x]).done&&(s.ready&(1u<<x)))candidates|=1u<<x;
      int winner=-1;for(unsigned k=0;k<3;k++){unsigned x=(rr+k)%3;if(candidates&(1u<<x)){winner=x;break;}}
      int64_t retiring=winner<0?-1:head[winner];
      auto after=occ;if(winner>=0)--after[winner];unsigned used_after=after[0]+after[1]+after[2],shared=0;for(unsigned n:after)if(n>1)shared+=n-1;
      unsigned expected_ready=0;for(unsigned x=0;x<3;x++)if(used_after<9&&(after[x]==0||shared<6))expected_ready|=1u<<x;
      bool accept=false; // Computed after final stimulus gating below.
      bool success=false;unsigned req=0;
      if(issue>=0){const auto&r=get(issue).r;req=1u<<bank(r);success=(s.argrant&req)&&(s.rwgrant&req);}
      std::vector<uint64_t> pending;for(const auto&c:cmds)if(!c.issued)pending.push_back(c.seq);
      std::vector<uint64_t> pool;for(auto q:pending)if(!(success&&int64_t(q)==issue))pool.push_back(q);
      int64_t selection=-1;for(size_t i=0;i<std::min<size_t>(5,pool.size());i++)if(int64_t(pool[i])!=issue&&idle(get(pool[i]).r,s.status)){selection=pool[i];break;}
      int64_t capture=returns.count(cycle)?int64_t(returns.at(cycle)):-1;
      Words memory={0xdeadc0deu^uint32_t(cycle),0xbaadf00du,0x55555555u,0xaaaaaaaau};bool perror=(cycle&1);
      if(capture>=0){auto&c=get(capture);memory=pattern(c.seq,c.r);perror=c.r.parity;}
      dut->clk=0;dut->arvalid=0;dut->araddr=s.request.addr;dut->src=s.request.src;dut->arid=s.request.id;dut->ar_port_id=s.request.port;dut->arresp=s.request.resp;dut->rready=s.ready;dut->rd_mem_status=s.status;dut->ar_rd_gnt=s.argrant;dut->rw_rd_gnt=s.rwgrant;dut->pc_err=perror;for(unsigned i=0;i<4;i++)dut->mem_rdata[i]=memory[i];eval_dump();
      // Obey the actual DUT input contract even when a mutant corrupts ready.
      // Expected ready remains independently calculated and compared below.
      s.valid=s.valid&&(dut->arready!=0);
      dut->arvalid=s.valid;eval_dump();
      if(s.valid&&dut->arready==0){s.valid=false;dut->arvalid=0;eval_dump();}
      accept=s.valid&&s.request.src<3&&(expected_ready&(1u<<s.request.src));
      equal(dut->req,req,"req");if(req)equal(dut->arb_addr,get(issue).r.addr>>6,"arb_addr");
      equal(dut->pending_cnt,pending.size(),"pending_cnt");equal(dut->arready,expected_ready,"arready");equal(dut->rvalid,winner<0?0:1u<<winner,"rvalid");
      check((dut->rvalid&~s.ready)==0,"rvalid directed to unready source");
      if(winner>=0){auto&c=get(retiring);for(unsigned i=0;i<4;i++)equal(dut->rdata[i],c.data[i],"rdata["+std::to_string(i)+"]");equal(dut->rid,c.r.id,"rid");equal(dut->r_port_id,c.r.port,"r_port_id");equal(dut->raddr,c.r.addr&7,"raddr");unsigned resp=c.r.resp==3?3:(c.r.parity?1:0);equal(dut->rresp,resp,"rresp");}
      check(cmds.size()<=9,"oracle total occupancy");unsigned reserve=0;for(unsigned x:occ){reserve+=std::max(x,1u);check(x<=7,"oracle per-source cap");}check(reserve<=9,"oracle reserve invariant");
      // Coverage is collected from independently predicted protocol events after comparisons.
      if(occ==std::array<unsigned,3>{7,0,0}&&winner<0)++cov["capacity700_ready110"];
      if(occ==std::array<unsigned,3>{4,4,0}&&winner<0)++cov["capacity440_ready100"];
      if(occ==std::array<unsigned,3>{7,1,1}&&winner==1&&expected_ready==2)++cov["unique_retire_ready010"];
      if(occ==std::array<unsigned,3>{7,1,1}&&winner==0&&expected_ready==7)++cov["shared_retire_ready111"];
      if(s.valid&&!accept)++cov["rejected_unready_src"];
      if(candidates==7)++cov["rr_all_three"];
      if(winner>=0&&unsigned(winner)!=rr)++cov["rr_skip"];
      if(s.ready==0&&std::any_of(cmds.begin(),cmds.end(),[](const auto&c){return c.done;}))++cov["ready_zero_holds_completed"];
      for(unsigned x=0;x<3;x++)if(head[x]>=0&&!get(head[x]).done){for(auto&c:cmds)if(c.r.src==x&&c.done){++cov["same_xau_head_block"];break;}}
      if(selection>=0&&success&&std::find(pending.begin(),pending.begin()+std::min<size_t>(5,pending.size()),uint64_t(selection))==pending.begin()+std::min<size_t>(5,pending.size()))++cov["sixth_success_forward"];
      if(selection<0&&issue<0&&pending.size()>5){bool busy=true;for(size_t i=0;i<5;i++)busy&=!idle(get(pending[i]).r,s.status);bool outside=false;for(size_t i=5;i<pending.size();i++)outside|=idle(get(pending[i]).r,s.status);if(busy&&outside)++cov["outside_window_blocked"];}
      if(req&&!success){event("issue_failure");get(issue).failed=true;if(selection>=0)++cov["failed_keep_next"];if((s.argrant&req)&&!(s.rwgrant&req))++cov["ar_only_grant"];if(!(s.argrant&req)&&(s.rwgrant&req))++cov["rw_only_grant"];if((s.argrant&s.rwgrant)!=0&&!(s.argrant&req)&&!(s.rwgrant&req))++cov["wrong_bank_grant"];}
      if(success){event("issued");auto&c=get(issue);++cov["issued_half_"+std::to_string(half(c.r))+"_bank_"+std::to_string(bank(c.r))];if(!idle(c.r,s.status))++cov["request_busy_but_granted"];if(c.failed)++cov["retry_success"];if(cycle-c.accepted==2)++cov["three_cycle_path"];for(auto&older:cmds){if(older.seq==c.seq)break;if(older.r.src==c.r.src&&!older.issued){++cov["same_xau_ooo_issue"];break;}}}
      if(capture>=0){event("captured");if(s.ready==0)++cov["capture_without_ready"];bool z=std::all_of(memory.begin(),memory.end(),[](uint32_t w){return w==0;});if(z&&!perror)++cov["zero_data_no_error"];if(last.count("prior_capture")&&last["prior_capture"]<int64_t(cycle)-1)++cov["capture_after_bubble"];last["prior_capture"]=cycle;++cov["capture_no_bypass"];}
      if(winner>=0){event("retired");++cov["retired_src"+std::to_string(winner)];auto&r=get(retiring).r;++cov["error_combo_"+std::to_string(r.resp==3?1:0)+std::to_string(r.parity?1:0)];}
      if(accept){for(const auto&old:cmds)if(old.r.src==s.request.src&&old.r.id==s.request.id){++cov["duplicate_live_id"];break;}for(const auto&old:cmds)if(old.r.src==s.request.src&&old.r.id>s.request.id){++cov["nonmonotonic_live_id"];break;}event("accepted");++cov["accepted_src"+std::to_string(s.request.src)];if(winner>=0&&cmds.size()==9)++cov["full_reuse"];if(winner>=0&&unsigned(winner)==s.request.src&&occ[winner]==7)++cov["single_source_turnover"];}
      if(accept&&success&&capture>=0&&winner>=0)++cov["four_events"];
      // One edge commits all independent events. No capture is visible to response choice above.
      dut->clk=1;eval_dump();
      if(success){get(issue).issued=true;check(!returns.count(cycle+4),"return calendar collision");returns[cycle+4]=issue;}
      if(capture>=0){auto&c=get(capture);check(c.issued&&!c.done,"capture belongs to unique in-flight request");c.done=true;c.data=memory;returns.erase(cycle);}
      if(winner>=0){cmds.erase(std::remove_if(cmds.begin(),cmds.end(),[&](auto&c){return int64_t(c.seq)==retiring;}),cmds.end());rr=(winner+1)%3;}
      if(accept){Command c;c.seq=seq_next++;c.accepted=cycle;c.r=s.request;cmds.push_back(c);++sent;}
      issue=selection;++cycle;
    }
    void phase(){for(unsigned c=0;c<cfg.cycles;c++)step(drive(c));for(unsigned n=0;n<200&&(!cmds.empty()||issue>=0||!returns.empty());n++)step(drive(n,true));check(cmds.empty()&&issue<0&&returns.empty(),"drain did not complete");for(int n=0;n<3;n++)step(Stim{});}
    void run(){reset();phase();if(cfg.type=="reset_clean"){++cov["drained_reset"];reset();phase();}for(auto&[k,n]:cfg.required)check(cov[k]>=n,"required coverage "+k+" reached "+std::to_string(cov[k])+" < "+std::to_string(n));check(cov["accepted"]==cov["retired"],"accepted/retired mismatch after drain");}
};
static void write_result(const fs::path&path,const std::string&status,const std::string&failure,const Config&cfg,const Bench*b){
 std::ofstream f(path);f<<"{\n  \"status\": \""<<status<<"\",\n  \"checks_failed\": "<<(status=="fail"?1:0)<<",\n  \"failure\": \""<<escape(failure)<<"\",\n  \"type\": \""<<escape(cfg.type)<<"\",\n  \"seed\": "<<cfg.seed<<",\n  \"cycles\": "<<(b?b->cycle:0)<<",\n  \"checks\": "<<(b?b->checks:0)<<",\n  \"coverage\": {";bool first=true;if(b)for(auto&[k,v]:b->cov){if(!first)f<<",";f<<"\n    \""<<escape(k)<<"\": "<<v;first=false;}f<<"\n  }\n}\n";
}
int main(int argc,char**argv){
 std::string case_path,result_dir="results";bool force_trace=false;
 for(int i=1;i<argc;i++){std::string a=argv[i];if(a=="--case"&&i+1<argc)case_path=argv[++i];else if(a=="--result-dir"&&i+1<argc)result_dir=argv[++i];else if(a=="--trace")force_trace=true;else{std::cerr<<"CONFIG_ERROR unknown argument "<<a<<"\n";return 2;}}
 if(case_path.empty()){std::cerr<<"CONFIG_ERROR --case is required\n";return 2;}
 fs::create_directories(result_dir);auto stem=fs::path(case_path).stem().string();auto json=fs::path(result_dir)/(stem+".json"),wave=fs::path(result_dir)/(stem+".vcd");Config cfg;std::unique_ptr<Bench>b;
 try{cfg=read_config(case_path);b=std::make_unique<Bench>(cfg,wave.string());b->run();write_result(json,"pass","",cfg,b.get());std::cout<<"PASS "<<stem<<" checks="<<b->checks<<" accepted="<<b->cov["accepted"]<<" cycles="<<b->cycle<<"\n";b.reset();if(!cfg.trace&&!force_trace)fs::remove(wave);return 0;}
 catch(const std::invalid_argument&e){write_result(json,"error",e.what(),cfg,b.get());std::cerr<<"CONFIG_ERROR "<<e.what()<<"\n";return 2;}
 catch(const std::exception&e){write_result(json,"fail",e.what(),cfg,b.get());std::cerr<<"CHECK_FAILED "<<stem<<" "<<e.what()<<"\n";return 1;}
}
