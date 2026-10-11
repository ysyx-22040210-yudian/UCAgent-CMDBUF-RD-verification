# UCAgent 现有 GUI：SBY / FormalMC 一键切换

当前项目的 UCAgent 执行服务已更新，原 SBY 阶段任务保持完成状态。更新后的桌面客户端在原任务页提供 **切换到 FormalMC** 按钮，点击一次直接进入完整项目的 FormalMC 操作界面。

## 当前电脑

已建立到虚拟机任务服务的本地转发 `http://127.0.0.1:18814`。`Start-UCAgent-CMDBUF.pyw` 打开更新后的 UCAgent 并定位到原 SBY 任务。此入口不会自动运行工具。

1. 在原 SBY 页面点击“切换到 FormalMC”。
2. 按实际安装情况填写 FormalMC 在执行设备上的工具路径，保存。
3. 点击“环境检查”“能力自检”或“运行完整验证”。
4. 顶部按钮可以切回 SBY。配置、运行记录和结果分别保存。

当前转发仅在本机保持运行；重新启动电脑后，可先建立 SSH 转发：

```sh
ssh -L 18814:127.0.0.1:8814 root@192.168.31.116
```

登录凭据不保存在本交付物中。

## 其他已有 UCAgent / FormalMC 的设备

客户端和执行服务需配套更新。此目录包含 `UCAgent-Desktop.pyz`、完整更新源包 `UCAgent-GUI-dual-backend-source.zip` 和可审查增量 `gui_patch.zip`。完整 RTL 验证输入仍使用上一版 `cmdbuf_rd_dual_backend.tar.gz`；本次没有修改 RTL、监视器、检查点或求解模型。

在已有 UCAgent Python 环境中使用更新源包，给服务启动命令增加：

```sh
--portable-formal-registry /path/to/portable-formal.json
```

登记模板及说明位于更新源包的 `docs/content/02_usage/13_portable_formal_gui.md`。设置包的本机路径、真实 SBY 任务 ID 和工具安装路径后，GUI 就能关联原 SBY 任务并打开完整双后端项目。不要照搬本虚拟机的绝对安装路径。增量补丁必须先核对 `change_manifest.json` 中的源文件哈希；不同版本不能盲目覆盖。

桌面客户端入口：

```sh
python3 UCAgent-Desktop.pyz --server http://127.0.0.1:8814
```

## 实际验证

- 桌面测试：82/82 通过。
- 服务端及平台入口回归：39/39 通过。
- 真实 UCAgent GUI + 已部署服务：原 SBY 页一键进入 FormalMC，来回切换无求解请求，配置草稿及结果独立。
- 新入口实际执行 SBY 环境检查及 `quota_math` 单任务证明通过；单任务明确显示为部分验证，不算全套通过。
- 当前设备没有 FormalMC。真实环境检查显示工具缺失，并保留错误日志；没有伪造 FormalMC PASS。
- 原 SBY 阶段任务的版本、状态和阶段记录在部署及界面测试前后保持一致。

新的 GUI 运行使用独立验证包的证据格式，不改写原 UCAgent 14 阶段签名验收。原始完整 SBY 107 项安全性质及 65 项覆盖的证据随上一版运行包保留。
