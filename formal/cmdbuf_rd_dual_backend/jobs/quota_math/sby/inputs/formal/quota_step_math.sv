`default_nettype none
// Pure universal arithmetic lemma. This is a supplier, not the DUT proof.
// No input assumptions are used: the legal domain is an implication guard.
module quota_step_math(
 input wire clk,
 input wire [3:0] c0,c1,c2,
 input wire [2:0] ret,
 input wire alloc_valid,
 input wire [1:0] alloc_src
);
 reg [3:0] c[0:2],d[0:2],n[0:2];
 reg [5:0] cost,used,shared,ncost,dcost;
 reg [2:0] ready;
 reg domain,ret_legal,accept,cap7,empty_ready;
 always @*begin
   c[0]=c0;c[1]=c1;c[2]=c2;
   cost=0;used=0;shared=0;ncost=0;dcost=0;
   ret_legal=$onehot0(ret);domain=1;
   for(integer x=0;x<3;x=x+1)begin
     cost=cost+((c[x]==0)?6'd1:{2'b0,c[x]});
     domain=domain && c[x]<=7;
     ret_legal=ret_legal && (!ret[x] || c[x]!=0);
     d[x]=c[x]-4'(ret[x]);
     used=used+{2'b0,d[x]};
     shared=shared+((d[x]>0)?({2'b0,d[x]}-6'd1):6'd0);
     dcost=dcost+((d[x]==0)?6'd1:{2'b0,d[x]});
   end
   domain=domain && cost<=9 && ret_legal;
   for(integer x=0;x<3;x=x+1)
     ready[x]=(used<9) && ((d[x]==0)||(shared<6));
   accept=alloc_valid && ((alloc_src==0 && ready[0])||(alloc_src==1 && ready[1])||(alloc_src==2 && ready[2]));
   cap7=1;empty_ready=1;
   for(integer x=0;x<3;x=x+1)begin
     n[x]=d[x]+4'(accept && alloc_src==x);
     ncost=ncost+((n[x]==0)?6'd1:{2'b0,n[x]});
     cap7=cap7 && n[x]<=7;
     empty_ready=empty_ready && (d[x]!=0 || ready[x]);
   end
 end
 always @(posedge clk)begin
   QUOTA_AFTER_BUDGET: assert(!domain || dcost<=9);
   QUOTA_NEXT_BUDGET: assert(!domain || ncost<=9);
   QUOTA_NEXT_MAX7: assert(!domain || cap7);
   QUOTA_AFTER_TOTAL: assert(!domain || used<=9);
   QUOTA_AFTER_SHARED: assert(!domain || shared<=6);
   QUOTA_EMPTY_READY: assert(!domain || empty_ready);
 end
endmodule
