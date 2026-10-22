// 九项“值集合”：每项保存一次尚未被消费的输入值，不保存事务年龄或顺序。
// 相同值允许占多项；pop 每次只删除其中一项，不能把重复值一次全部删掉。
// qualify 只限制匹配资格，不影响已存值的有效性。无有效项时，清零数据不能匹配。
// 本模块只供简化检查器使用；它不访问、也不模拟 DUT 的物理 entry 编号。
`default_nettype none
module cmdbuf_rd_value_bag #(
    parameter integer WIDTH = 8 // 每项值的位宽；容量固定为本项目的九项。
) (
    input wire clk, // 采样时钟。
    input wire rst_n, // 低有效复位，建立空集合；不增加复位协议假设。
    input wire push, // 本拍保存一个新值。
    input wire [WIDTH-1:0] push_value, // 本拍新值。
    input wire pop, // 本拍消费一个匹配值；查询但未消费时为 0。
    input wire [WIDTH-1:0] query_value, // 与各项逐项相等比较的输出值。
    input wire [8:0] qualify, // 每项是否有资格参与本拍匹配。
    output reg [8:0] valid, // 每项有无尚未消费的值；pop 清除，push 置位。
    output reg [WIDTH-1:0] value [0:8], // 九项值记录，只有 valid 为 1 的项参与匹配。
    output wire [8:0] match_mask, // 九项逐项匹配结果。
    output wire hit, // 至少一项匹配；不要求匹配项具有某个指定编号。
    output wire room, // 存在空槽，或本拍 pop 成功后能立即复用一个槽。
    output wire [8:0] pop_slot, // 本拍实际删除的一项，最多一位有效。
    output wire [8:0] push_slot, // 本拍实际分配的一项，最多一位有效。
    output wire [3:0] count // 拍初尚未消费的项数，供检查模型账本自洽。
);
    wire [9:0] match_prefix; // prefix[k]：前 k 个槽是否已经找到匹配。
    wire [9:0] free_prefix; // prefix[k]：前 k 个槽是否已经找到可分配项。
    wire [8:0] free_slot; // 原空槽和本拍成功消费槽组成的可分配集合。
    wire [3:0] count_prefix [0:9]; // 对前 k 个有效位求和，全部为本拍组合结果。
    genvar g; // 展开九个槽的比较、优先选择及计数电路。

    // 扫描开始尚未找到匹配；prefix 的下标不是时钟拍数。
    assign match_prefix[0] = 1'b0;
    // 扫描开始尚未找到空位。
    assign free_prefix[0] = 1'b0;
    // 尚未扫描任何槽时，有效项数为零。
    assign count_prefix[0] = 4'd0;
    generate for (g=0; g<9; g=g+1) begin : slots
        // 无效项、未具备资格的项不能因数据恰好相同而命中。
        assign match_mask[g] = valid[g] && qualify[g] && value[g]==query_value;
        // 保存“前面或当前存在匹配”，让后面的重复值不再被本次 pop 删除。
        assign match_prefix[g+1] = match_prefix[g] || match_mask[g];
        // 只删除第一个匹配值；槽号选择仅是集合存储策略，不表示事务顺序。
        assign pop_slot[g] = pop && match_mask[g] && !match_prefix[g];
        // 已消费的槽可以同拍写入新值，支持满集合时同进同出。
        assign free_slot[g] = !valid[g] || pop_slot[g];
        // 记录此前是否已有空槽，保证本次 push 只分配一项。
        assign free_prefix[g+1] = free_prefix[g] || free_slot[g];
        // 选择第一个可用槽；无空槽时不写入，由外层的溢出断言报告。
        assign push_slot[g] = push && free_slot[g] && !free_prefix[g];
        // 计数只看本拍更新前的 valid，不包含正在 push 的新值。
        assign count_prefix[g+1] = count_prefix[g] + {3'b0,valid[g]};
    end endgenerate
    // 任一合法槽命中就认为本字段比较通过。
    assign hit = match_prefix[9];
    // 九槽扫描后有空位即可接收；包括本拍消费释放的槽。
    assign room = free_prefix[9];
    // 返回九个有效位的总数。
    assign count = count_prefix[9];

    integer i; // 时序更新使用的槽索引。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 9'b0;
            for (i=0; i<9; i=i+1) value[i] <= {WIDTH{1'b0}};
        end else begin
            for (i=0; i<9; i=i+1) begin
                // 新写入优先于旧值删除；同槽复用时不能把刚写入的新值清掉。
                if (push_slot[i]) begin
                    valid[i] <= 1'b1;
                    value[i] <= push_value;
                end else if (pop_slot[i]) begin
                    valid[i] <= 1'b0;
                    value[i] <= {WIDTH{1'b0}};
                end
            end
        end
    end
endmodule
`default_nettype wire
