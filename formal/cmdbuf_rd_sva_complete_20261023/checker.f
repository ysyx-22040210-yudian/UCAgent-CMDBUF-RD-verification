// 已有自己的 DUT/接入顶层时，只加入这份检查器清单，并连接全部公开接口。
// 需从本文件所在目录运行；实例化模块名为 cmdbuf_rd_port_sva。
// .svh 由 include 自动载入，不单独编译，不启用 optional 引导或违规环境。
+define+SYNTHESIS
+define+CMDBUF_CORNER_SUITE
+incdir+.
cmdbuf_rd_port_sva.sv
