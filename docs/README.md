# 文档索引

## 界面修复

- [按钮「阴影」问题：清单与修复记录](ui-button-shadow-fix.md)
  —— 根因（iOS 26 SDK 默认 Button 样式 / 容器投影）、逐按钮台账、
  三步修复方法、验收步骤、剩余待办。commit 起点 `462713d`。

## 设计与计划（项目原有）

- `lobster-cognitive-dev-plan-v2.1.md` … `v9.0.md` —— 认知架构迭代计划
- `workflow-session-refactor-plan.md` —— 会话工作流重构方案
- `ish-bg-cpu-governor-design.md` —— iSH 后台 CPU 调度设计
- `后期版本融合事项记录_v1.md` —— 上游融合事项台账
- `specs/` —— 规格文档

## 其它

- 构建与发版流程见仓库根目录 `BUILDING.md`；本 fork 的发版流水线为
  `.github/workflows/build-and-release.yml`（递增 `VERSION.txt` → 并行构建
  Android/iOS → 发布到本仓库与 `vbox-Ai/Lobster-APP`）。
