# 从 GitHub 使用当前项目

桌面的逐步操作和实际截图见 [Tk GUI 详细操作图示](gui/README.md)；下载后可打开 [离线阅读版](gui/index.html)。

## 原生桌面界面

客户端使用 Python 3.8+ 自带的 Tkinter/ttk；Linux 桌面系统需提供 Tk 和图形显示环境。执行服务使用 Python 3.11+ 和 `ucagent-tool/requirements.txt` 所列依赖。若已有相同 UCAgent 环境，先核对本仓库的 GUI 变更清单和版本，再配套更新客户端与服务。

```sh
python3 gui/UCAgent-Desktop.pyz --server http://127.0.0.1:8814
```

平台客户端入口显示原生 Tk 窗口，不打开浏览器报告。源码入口也可使用 `python3 ucagent-tool/desktop/ucagent_app.py --server http://127.0.0.1:8814`。

## 登记完整验证包

按照 [登记格式](../ucagent-tool/docs/content/02_usage/13_portable_formal_gui.md)，在执行设备建立本地登记 JSON，填写：

- `id`: `cmdbuf_rd`。
- `root`: 本仓库中 `formal/cmdbuf_rd_dual_backend` 的绝对路径。
- `session_ids`: 该执行设备真实的 SBY 阶段任务 ID；无现有任务时可以是空数组，从侧栏“双后端验证”进入。
- `default_configs`: 本机的 SBY、FormalMC 工具路径和超时配置。

给已有执行服务启动参数增加 `--portable-formal-registry /your/local/portable-formal.json`，保留原来的 workspace、工具链、导入目录及认证设置。源码服务入口是 `python3 -m ucagent.server.platform_main`，工作目录为 `ucagent-tool/`。新设备不会继承原虚拟机数据库或原任务完成状态。

连接后从“**双后端验证**”打开 `cmdbuf_rd`，选择 SBY / FormalMC，保存工具配置，执行环境检查、能力自检或完整验证。原 SBY 任务已登记关联时，可在任务页直接点击“切换到 FormalMC”。

## 本次原任务入口

`gui/Start-UCAgent-CMDBUF.pyw` 默认使用 `http://127.0.0.1:18814` 和原会话 ID，只适用于已连接本次虚拟机服务的当前电脑。可以通过 `--server` / `--session` 显式覆盖；其他电脑优先使用通用 zipapp 命令。

## 仿真与报告

`simulation/` 是早期开发交付的完整快照，工程原路径和 GCC/Verilator 要求保存在其 README 与 Makefile。新设备运行前按该工程的适配配置填写本机路径。已经可迁移且不依赖原虚拟机数据库的运行入口是 `formal/cmdbuf_rd_dual_backend/run.py`。

`verification/closure/` 原始归档经过完整离线校验并分卷上传。先运行 `tools/assemble_evidence.py`，再按原证据 README 校验全部 9,252 个载荷文件。普通 SHA 校验确认交付字节一致，不等同于持有原平台 HMAC 密钥的签名验证。
