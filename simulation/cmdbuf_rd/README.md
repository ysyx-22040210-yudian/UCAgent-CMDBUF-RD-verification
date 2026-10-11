# cmdbuf_rd RTL 与验证工程

开发与实际编译、仿真、注错验证主机：192.168.31.116，工程：`/root/cmdbuf_rd`。
本工程依据已对齐的 cmdbuf_rd 设计基线实现。当前为 RTL 功能验证交付，未进行综合面积、静态时序或完整形式证明。

## 实现结构

- `rtl/cmdbuf_rd.sv`：顶层接口、CMDBUF/OTB 连接。
- `rtl/cmdbuf_rd_cmd.sv`：9 项元数据与状态、年龄矩阵、最老 5 条待发窗口、三周期接收/判断/发射、5A/6B、容量准入、每 XAU 保序及响应 RR、10B 同拍复用。
- `rtl/cmdbuf_rd_otb.sv`：9 项 128-bit 数据与 pc_err、成功发射四拍返回标记、无返回背压的数据捕获、分配/退休数据清除。
- `/root/env_base/adapters/cmdbuf_rd/`：独立 C++ 参考模型和 Verilator 驱动。
- `/root/env_base/cases/cmdbuf_rd/`：定向及随机 case；公共 runner 未加入 DUT 特例。
- `scripts/run_mutations.py`：隔离 RTL 注错副本、编译与检测结果分类。
- `docs/`：设计来源、实现选择、用例及注错说明。
- `results/`：检查结果、逐用例 JSON/日志、需要保留的波形。

## 开发基线

AR 和 R 均共享负载，每周期最多接收、发射、捕获、返回各一条。arid 是透传标签，顺序由内部接收年龄决定。
`rd_mem_status[1:0][7:0]` 的第一个索引为奇偶 half，第二个索引为 bank；0 表示空闲。Arbit 地址为 12-bit `araddr[17:6]`。
CMDBUF 与 OTB 的 9 项一一对应，从合法 AR 握手起保留到实际 R 返回。

保留容量采用“每 XAU 1 项逻辑保底 + 6 项共享”，物理 entry 仍统一分配。占用包含所有已接收未返回命令；`sum(max(occ[x],1)) <= 9`。这是满足用户禁止容量独占要求的实现选择。上游仲裁公平性未确定，因此只保证容量不会被其他来源侵占，不能保证上游一定调度某个来源。

选择先构造成功前馈后的最老 5 条未成功发射命令，再按 Bank 空闲过滤并选最老；当前请求级命令不可重复选中。5A 失败不冲刷下一条预选；6B 成功当拍推进窗口；10B 返回当拍允许新接收复用。
成功取同一 req bank 上 `ar_rd_gnt` 和 `rw_rd_gnt` 同为 1。成功 C3 → MEM 捕获 C7 → 最早 R 返回 C8。
地址越界仍走 MEM，R 状态优先级为地址越界 11、奇偶异常 01、正常 00。R 仅在 ready 的已完成来源队头之间 RR。

## 已采用但需要系统集成确认的实现选择

1. 异步低有效 `rst_n`；所有状态和数据复位清零。运行中复位的 MEM 协同协议不包含在本次接口定义中，集成时仍需确认。
2. RR 顺序 0→1→2，复位起点 0，仅实际响应后更新为获胜来源的下一来源，空闲保持。
3. 错误响应的 rdata 仍透传已捕获的 MEM 数据，rresp 指示错误。
4. 选择进入请求级后，下一周期仍发送 req；Bank 状态变化由当拍双 grant 最终决定成功。
5. 无有效请求/响应时，输出负载置零。OTB 分配、退休和复位均物理清零数据。
6. src=3 不接受；已接受请求的 arresp 只允许 00/11。其他编码属于未定义输入，内部断言会报错。
7. 所有接口均同一时钟域；没有 CDC、ECC、超时或可变返回延迟处理。MEM 必须严格成功后四拍给出有效数据。

## 复现

在虚拟机中执行：

```sh
cd /root/cmdbuf_rd
make lint validate
make test
python3 scripts/run_mutations.py --help
```

`make test` 调用既有公共 runner；使用 `/opt/rh/devtoolset-11/enable` 中的 GCC 11，Verilator 5.024，C++17。不要使用系统默认 GCC 4.8 编译 harness。
常规结果在 `results/baseline/regression.json`；单个 case 可通过公共 Makefile 的 `run-case CASE=<绝对路径>` 运行。补充检查和注错的实际命令、统计以 `docs/verification_baseline.md`、`docs/mutation_plan.md` 及最终验证报告为准。

## 验证边界

独立参考模型按接收序号维护队列、返回日历和每来源队头，逐拍核对 req、地址、ready、pending 与完整 R 负载。RTL 内部断言额外检查容量、年龄和生命周期一致性。
注错检测区分参考模型、RTL 断言、构建失败、运行环境错误及漏检。既有 49 组注错清单是规格覆盖来源，不表示已经实际运行 49 种 RTL 变异。
测试通过不代表所有输入序列的形式证明，也不代表目标频率已经收敛。

本目录不保存 SSH 密码；本机源文件、结果及随交付包提供的 SHA256 用于追溯实际验证版本。
