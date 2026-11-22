# BookStark Flutter 改造

客户端在 [flutter_app](../../flutter_app/README.md)。本目录保存 [页面设计与原型](pages/) 和 [后端兼容性记录](backend-compatibility/)。[改造计划](../prototypes/flutter-rewrite-2026-11-04/rewrite-plan.md)记录整体范围。

该版本一并整理了 Flutter 端使用的后端改动，包括共享及个人内容的版本校验、受保护内容的编辑和恢复、书签／标签／专题的创建核对、专题摘要正文、笔记列表元数据、HTML 只读源码模式及 PPTist 阅读位置接口。

APK、临时镜像和环境专用运维配置在各环境中保管。后续验收可通过 Flutter 自带分析器和测试套件、Go 后端测试以及 NAS Redroid ARM64 测试完成。
