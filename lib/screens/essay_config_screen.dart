import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../recording_provider.dart';
import '../widgets/academic_markdown.dart';
import '../utils/pdf_service.dart';
import 'history_screen.dart';

class EssayConfigScreen extends StatefulWidget {
  const EssayConfigScreen({super.key});

  @override
  State<EssayConfigScreen> createState() => _EssayConfigScreenState();
}

class _EssayConfigScreenState extends State<EssayConfigScreen> {
  final _topicAController = TextEditingController(text: "Human Migration / Brain Drain");
  final _topicBController = TextEditingController(text: "Economic Development of Origin Countries");
  String _selectedLevel = "Academic Advanced (TOEFL 100)";
  String _selectedModel = "llama70b"; // 默认首选 Llama 3.3 70B (Groq)
  bool _isGenerating = false;
  String? _resultMarkdown;
  String? _errorMessage;
  String? _savedFilePath;

  // 用于 PDF 导出按钮的 GlobalKey（iPad popover 锚点）
  final GlobalKey _pdfButtonKey = GlobalKey();

  final List<String> _levels = [
    "Academic Intermediate (IELTS 6.5)",
    "Academic Advanced (TOEFL 100)",
    "Hardcore C2 (Oxford/Cambridge)"
  ];

  final List<Map<String, String>> _models = [
    {"value": "llama70b", "label": "Llama 3.3 70B (Groq - ⚡ 极速约10秒)"},
    {"value": "qwen32b", "label": "Qwen 2.5 32B (硅基 - 🚀 较快约30秒)"},
    {"value": "qwen72b", "label": "Qwen 2.5 72B (硅基 - 🐢 慢约60秒)"},
  ];

  @override
  void dispose() {
    _topicAController.dispose();
    _topicBController.dispose();
    super.dispose();
  }

  String _getModelLabel(String val) {
    for (var m in _models) {
      if (m['value'] == val) return m['label'] ?? val;
    }
    return val;
  }

  String _getEstimatedTimeTip(String model) {
    if (model == 'llama70b') {
      return "⏱ 预计仅需 5–15 秒，请确认后再生成。";
    } else if (model == 'qwen32b') {
      return "⏱ 预计需要 15–40 秒，请确认后再生成。";
    } else {
      return "⏱ 预计需要 30–90 秒，请确认后再生成。";
    }
  }

  String _getLoadingLabel() {
    if (_selectedModel == 'llama70b') {
      return "Invoking Llama-3.3-70B... (预计 5–15 秒)";
    } else if (_selectedModel == 'qwen32b') {
      return "Invoking Qwen-32B... (预计 15–40 秒)";
    } else {
      return "Invoking Qwen-72B... (预计 30–90 秒)";
    }
  }

  // ── 问题1：误触确认弹窗 ───────────────────────────────
  Future<void> _confirmAndGenerate() async {
    final topicA = _topicAController.text.trim();
    final topicB = _topicBController.text.trim();

    if (topicA.isEmpty || topicB.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Topic A 和 Topic B'), backgroundColor: Colors.orange),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('确认生成', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('即将调用 AI 模型生成作文矩阵：', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            _confirmRow('Topic A', topicA),
            const SizedBox(height: 6),
            _confirmRow('Topic B', topicB),
            const SizedBox(height: 6),
            _confirmRow('Level', _selectedLevel),
            const SizedBox(height: 6),
            _confirmRow('Model', _getModelLabel(_selectedModel)),
            const SizedBox(height: 12),
            Text(_getEstimatedTimeTip(_selectedModel),
                style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认生成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _generateMatrix();
    }
  }

  Widget _confirmRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          TextSpan(text: value),
        ],
      ),
    );
  }

  // ── 核心生成逻辑（含自动重试一次）────────────────────
  Future<void> _generateMatrix() async {
    final provider = context.read<RecordingProvider>();
    setState(() {
      _isGenerating = true;
      _resultMarkdown = null;
      _errorMessage = null;
      _savedFilePath = null;
    });

    try {
      final result = await _tryGenerate(provider);
      // 生成成功后自动保存到 MD 文件
      final savedPath = await _saveToMarkdown(result);
      setState(() {
        _resultMarkdown = result;
        _savedFilePath = savedPath;
        _isGenerating = false;
      });
      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✅ 作文矩阵已自动保存到历史记录'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: '查看',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HistoryScreen()),
                  );
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 作文生成成功，但自动保存本地失败'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
        _isGenerating = false;
      });
    }
  }

  // 自动重试一次（先试主调用，失败后等 5 秒再重试）
  Future<String> _tryGenerate(RecordingProvider provider) async {
    try {
      return await provider.generateEssayMatrix(
        _topicAController.text.trim(),
        _topicBController.text.trim(),
        _selectedLevel,
        model: _selectedModel,
      );
    } catch (firstError) {
      debugPrint('[EssayMatrix] First attempt failed: $firstError — retrying in 5s...');
      await Future.delayed(const Duration(seconds: 5));
      // 第二次重试
      return await provider.generateEssayMatrix(
        _topicAController.text.trim(),
        _topicBController.text.trim(),
        _selectedLevel,
        model: _selectedModel,
      );
    }
  }

  // ── 问题3：自动保存 MD 文件 ──────────────────────────
  Future<String?> _saveToMarkdown(String content) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      // 允许中文字符，仅移除非法文件名字符，并将空格替换为下划线
      final topicA = _topicAController.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_');
      final filename = "Jeff_Essay_${topicA}_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(content);
      debugPrint('[Essay Export] Saved to ${file.absolute.path}');
      return file.absolute.path;
    } catch (e) {
      debugPrint('[Essay Export Error] $e');
      return null;
    }
  }

  // PDF 导出
  Future<void> _exportPdf() async {
    if (_resultMarkdown == null) return;
    try {
      final topicA = _topicAController.text.trim();
      final title = 'Jeff_Essay_${topicA.replaceAll(' ', '_')}.pdf';

      Rect? bounds;
      final renderBox = _pdfButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final offset = renderBox.localToGlobal(Offset.zero);
        bounds = offset & renderBox.size;
      }

      await PdfService.exportToPdf(title, _resultMarkdown!, bounds: bounds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ PDF 导出失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Essay Architect",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu),
            tooltip: "查看历史记录",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F0F1A), const Color(0xFF161626), const Color(0xFF1E1C2C)]
                : [const Color(0xFFF7F8FC), const Color(0xFFEEF1F7), const Color(0xFFE5E9F3)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Intro Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      )
                    ],
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.psychology_outlined, color: Colors.blueAccent, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Writing Lab Logic Matrix",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Compare any two topics to automatically structure arguments and extract high-yield EAL chunks.",
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form Section
                Text(
                  "Architecture Configuration",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),

                // Inputs Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      )
                    ],
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _topicAController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: "Topic A (Subject)",
                          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _topicBController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: "Topic B (Comparison Target)",
                          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: _selectedLevel,
                        dropdownColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: "Target EAL Vocabulary Level",
                          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                        items: _levels.map((level) {
                          return DropdownMenuItem<String>(
                            value: level,
                            child: Text(level),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedLevel = val);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: _selectedModel,
                        dropdownColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: "AI Model Selection",
                          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                        items: _models.map((model) {
                          return DropdownMenuItem<String>(
                            value: model['value'],
                            child: Text(model['label'] ?? ''),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedModel = val);
                          }
                        },
                      ),
                      const SizedBox(height: 28),

                      // Generate Button — 改为先弹确认框
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isGenerating ? null : _confirmAndGenerate,
                          child: _isGenerating
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      "Architecting Matrix...",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                )
                              : const Text(
                                  "Generate Essay Matrix",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('❌ 生成失败（已自动重试一次）',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(_errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        const SizedBox(height: 8),
                        const Text('提示：硅基流动 Qwen-72B 高峰期响应较慢，可稍后再试。',
                            style: TextStyle(color: Colors.orange, fontSize: 12)),
                      ],
                    ),
                  ),

                // 生成中的进度条
                if (_isGenerating)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Column(
                        children: [
                          const LinearProgressIndicator(color: Colors.blueAccent),
                          const SizedBox(height: 16),
                          Text(
                            _getLoadingLabel(),
                            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "如超时将自动重试一次，请耐心等待",
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[600] : Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Results Section
                if (_resultMarkdown != null) ...[
                  // 已保存提示
                  if (_savedFilePath != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '已自动保存到历史记录（可在 History 中查看）',
                              style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 结果标题 + 操作按钮行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Generated Structure Matrix",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      // 操作按钮组
                      Row(
                        children: [
                          // 复制全文
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: Colors.blueAccent),
                            tooltip: '复制全文',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _resultMarkdown!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("✅ 已复制到剪贴板")),
                              );
                            },
                          ),
                          // PDF 导出
                          IconButton(
                            key: _pdfButtonKey,
                            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.deepPurpleAccent),
                            tooltip: '导出 PDF',
                            onPressed: _exportPdf,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2F) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        )
                      ],
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                      ),
                    ),
                    child: MarkdownBody(
                      data: _resultMarkdown!,
                      softLineBreak: true,
                      styleSheet: getAcademicMarkdownStyle(context),
                      selectable: true,
                      extensionSet: md.ExtensionSet(
                        [const md.FencedCodeBlockSyntax()],
                        [md.EmojiSyntax(), HighlightSyntax()],
                      ),
                      builders: {
                        'highlight': HighlightBuilder(context),
                      },
                    ),
                  ),
                  const SizedBox(height: 40),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
