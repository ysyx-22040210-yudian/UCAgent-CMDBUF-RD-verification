// 从本文件所在目录运行；此清单含当前 RTL、完整检查器和 formal 顶层。
// 编译顶层为 cmdbuf_rd_formal；三个 RTL 文件与主检查器各编译一次。
// .svh 已由主检查器逐层 include，不应再次作为独立编译单元加入。
// CMDBUF_CORNER_SUITE 启用全部 Corner 属性；optional 中的额外环境不在此清单。
+define+SYNTHESIS
+define+CMDBUF_CORNER_SUITE
+incdir+.
rtl/cmdbuf_rd.sv
rtl/cmdbuf_rd_cmd.sv
rtl/cmdbuf_rd_otb.sv
cmdbuf_rd_port_sva.sv
formal_top.sv
