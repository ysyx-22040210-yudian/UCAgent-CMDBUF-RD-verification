# 交付来源

本仓库是 2026-10-12 项目交付快照。原始可迁移形式输入、RTL、模型和证据均按字节复制；`formal/cmdbuf_rd_dual_backend/release_hashes.json` 保持原清单。

UCAgent 源码来自已验收的 GUI 工程副本。源码里的 `SOURCE_SNAPSHOT.json` 是先前平台快照来源记录，不能作为本次修改后源码的当前哈希清单；本次 GUI 变更由 `gui_change_manifest.json` 记录，仓库内全部交付文件由根目录 `publication_manifest.json` 记录。

原始完整证据归档没有重新压缩或改写，只按字节分为小于 50 MiB 的 5 个文件。`verification/closure/evidence_parts.json` 同时保存每卷与整包的长度和 SHA256。

上游 UCAgent 源码的 Apache-2.0 许可证完整保存在 `ucagent-tool/LICENSE`，本仓库不重新许可或捆绑第三方 EDA 工具和运行时。缓存、当前客户端偏好、平台整库、认证信息和机器本地启动凭据不在此次交付范围内。
