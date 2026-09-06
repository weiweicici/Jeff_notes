# 阅读与语法模块移除交接

## 完成范围

- 删除阅读入口、阅读页面、Pathways 本地内容、阅读解析器，以及仅供阅读页面使用的 AI 题目、摘要、词汇和 Pathways 请求。
- 删除语法入口、页面、课程数据、仓库、生成服务、草稿/Watch 写作流程、速查资源和专属测试。
- 删除 Watch 的语法写作入口、配置、请求、状态同步和原生传输桥接；听力录音、全部文档和播放控制保留。
- 历史记录不删除：云端查询仍包含既有 `module=reading` 和 `module=grammar`，使旧记录继续在“全部文档”可见；只移除两个已停用模块的筛选项和新入口。

## 删除文件

- `lib/data/grammar_content.dart`
- `lib/data/pathways_content.dart`
- `lib/screens/grammar_detail_screen.dart`
- `lib/screens/grammar_part_list_screen.dart`
- `lib/screens/grammar_screen.dart`
- `lib/screens/grammar_writing_screen.dart`
- `lib/screens/reading_detail_screen.dart`
- `lib/screens/reading_screen.dart`
- `lib/screens/reading_session_screen.dart`
- `lib/services/grammar_exam_reference_service.dart`
- `lib/services/grammar_repository.dart`
- `lib/services/grammar_service.dart`
- `lib/services/grammar_writing_draft_service.dart`
- `lib/services/reading_content_parser.dart`
- `assets/grammar/ultimate_grammar_quick_reference.md`
- 五个语法专属测试文件。

## 共享内容保留

- `lib/services/reading_quiz_service.dart` 仅保留划词翻译和英文转述，因为 `note_detail_screen.dart` 仍调用它；阅读题目功能已移除。
- 写作、听力、录音、历史、设置、TTS 和词汇实现未按模块名称删除。
- `PathwaysUnit` 及其与听力/复习提示相关的既有序列化值保留；不清理旧用户文档或云端记录。

## 备份

- 精确目标的可恢复副本位于 `tmp/reading-grammar-removal-backup-20260906/`；备份内 Dart 文件以 `.dart.bak` 保存，避免 Flutter 将其当作项目源码分析。
- 备份仅含本次目标源码、测试和 Markdown 资源；不含密钥、IPA、录音或构建物。

## 验证

- `flutter analyze`：无 error；现有项目有 136 条 info/warning（未处理，未新增错误）。
- `flutter test test/release_hardening_test.dart test/watch_offline_companion_test.dart`：13 passed。
- 入口/静态引用检索：已确认阅读/语法页面、专属服务、Watch 请求和桥接符号无残留；历史查询刻意保留既有模块值以读取旧记录。

## 未验证事项

- 未执行 iOS archive、真机安装或 Apple Watch 配对回归；没有打包、提交或推送。
