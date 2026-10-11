
# SBY / FormalMC 一键切换

完整双后端项目可以在 UCAgent 现有桌面 GUI 内运行。它使用包内同一份检查点清单，分别调用 SBY 和 FormalMC 入口。传统 guided 工程的迁移功能继续保留。

## 操作

1. 启动更新后的 UCAgent 桌面客户端，连接匹配版本的执行服务。
2. 打开已关联完整验证包的 SBY 阶段任务，点击“切换到 FormalMC”。界面直接进入该项目的 FormalMC 操作页。
3. 工具不在服务进程的 PATH 中时，填写其在执行设备上的安装路径，保存配置。
4. 点击环境检查、能力自检或完整验证。完整 FormalMC 验证会执行运行器自带的能力自检。
5. 使用顶部 SBY / FormalMC 按钮随时切换。两个后端分别保存配置、日志及结果。

切换页面不会启动工具，也不会创建新的阶段验收结论。运行中的任务始终归属启动它的后端；切换页面不会重启或改用另一工具。服务同时只接受一个新任务，停止按钮针对真实活动任务。

## 服务登记

管理员启动执行服务时添加 `--portable-formal-registry /path/to/portable-formal.json`。现有 workspace、工具链、导入目录及身份配置继续沿用。

登记文件示例：

```json
{
  "schema_version": 1,
  "packages": [
    {
      "id": "cmdbuf_rd",
      "title": "cmdbuf_rd",
      "root": "/work/cmdbuf_rd_dual_backend",
      "session_ids": ["关联的SBY阶段任务ID"],
      "default_configs": {
        "sby": {
          "tool": "/opt/oss-cad-suite/bin/sby",
          "tool_dirs": ["/opt/oss-cad-suite/bin"],
          "timeout": 1200,
          "sby_timeout": 900
        },
        "formalmc": {
          "tool": "/opt/formalmc/bin/FormalMC",
          "tool_dirs": [],
          "timeout": 1200
        }
      }
    }
  ]
}
```

`root` 必须指向管理员审查过、包含 `run.py`、`manifest.json` 和 `release_hashes.json` 的完整运行包。服务账户应能读取该目录。工具路径、许可证和运行环境以服务所在设备为准，不是桌面客户端所在设备。服务账户的许可证环境仍由管理员设置，GUI 不收集许可证密钥。

`session_ids` 只建立导航关联，不修改原任务的证据和完成状态。也可以从桌面的双后端验证入口打开已登记项目。迁移后的新设备应填写其自身目录和任务 ID，不复制旧主机的绝对路径。

## 结果语义

环境检查通过、能力自检通过、部分任务通过、完整证明通过分别显示。只有当前后端完整执行并满足全部检查点时，才能显示完整通过。FormalMC 初始为尚未运行，不继承 SBY 的结论。缺工具、许可证失败、编译错误、超时和未识别结果均保留诊断。

这些运行仍使用双后端包的独立证据格式；不会替代 UCAgent 原 14 阶段签名验收。当前开发设备没有真实 FormalMC，界面接入和 SBY 实测不能被解释为已经完成 FormalMC 实机证明。
