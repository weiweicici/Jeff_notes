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

enum EssayCategory {
  transportation,
  technology,
  lifestyle,
  school,
  career,
  media,
}

class PresetTopic {
  final String topic;
  final String chineseLabel;

  const PresetTopic({required this.topic, required this.chineseLabel});
}

const Map<EssayCategory, List<PresetTopic>> presetTopicsByCategory = {
  EssayCategory.transportation: [
    PresetTopic(topic: "Taking the bus vs. Driving a private car", chineseLabel: "坐公交 vs 开私家车"),
    PresetTopic(topic: "Taking the train vs. Flying by airplane", chineseLabel: "坐火车 vs 坐飞机"),
    PresetTopic(topic: "Wearing face masks vs. Not wearing face masks", chineseLabel: "戴口罩 vs 不戴口罩"),
    PresetTopic(topic: "Wearing bicycle helmets vs. Not wearing bicycle helmets", chineseLabel: "戴头盔 vs 不戴头盔"),
    PresetTopic(topic: "Using public transit vs. Using ride-sharing apps (like Uber)", chineseLabel: "公共交通 vs 打车软件"),
    PresetTopic(topic: "Buying an electric vehicle (EV) vs. Buying a gas car", chineseLabel: "买电动车 vs 买燃油车"),
  ],
  EssayCategory.technology: [
    PresetTopic(topic: "Online learning vs. Traditional classroom learning", chineseLabel: "在线学习 vs 传统课堂"),
    PresetTopic(topic: "E-books vs. Printed textbooks", chineseLabel: "电子书 vs 纸质教材"),
    PresetTopic(topic: "Working from home (Remote) vs. Working in the office", chineseLabel: "居家办公 vs 办公室工作"),
    PresetTopic(topic: "Using cash vs. Using digital/mobile payment", chineseLabel: "现金支付 vs 移动支付"),
    PresetTopic(topic: "Shopping online vs. Shopping in traditional stores", chineseLabel: "网购 vs 实体店购物"),
    PresetTopic(topic: "Using AI tools for study vs. Doing research completely by oneself", chineseLabel: "用 AI 学习 vs 完全自主研究"),
  ],
  EssayCategory.lifestyle: [
    PresetTopic(topic: "Living in a big city vs. Living in a small town", chineseLabel: "住大城市 vs 住小城镇"),
    PresetTopic(topic: "Cooking at home vs. Eating at restaurants", chineseLabel: "在家做饭 vs 下馆子"),
    PresetTopic(topic: "Using plastic bags (Paid) vs. Bringing reusable bags", chineseLabel: "用塑料袋 vs 自带环保袋"),
    PresetTopic(topic: "Renting a house vs. Buying a house", chineseLabel: "租房 vs 买房"),
    PresetTopic(topic: "Going to the gym vs. Exercising outdoors", chineseLabel: "去健身房 vs 户外运动"),
    PresetTopic(topic: "Traveling domestically vs. Traveling internationally", chineseLabel: "国内旅游 vs 出国旅游"),
  ],
  EssayCategory.school: [
    PresetTopic(topic: "Free school lunches vs. Paid school lunches", chineseLabel: "免费午餐 vs 付费午餐"),
    PresetTopic(topic: "Studying alone vs. Studying in groups", chineseLabel: "独自学习 vs 小组学习"),
    PresetTopic(topic: "Taking notes by hand vs. Typing notes on a laptop", chineseLabel: "手写笔记 vs 电脑打字"),
    PresetTopic(topic: "Wearing school uniforms vs. Casual dress code", chineseLabel: "穿校服 vs 自由着装"),
    PresetTopic(topic: "Mandatory class attendance vs. Optional class attendance", chineseLabel: "强制上课 vs 自愿上课"),
    PresetTopic(topic: "Banning smartphones in school vs. Allowing smartphones in school", chineseLabel: "校园禁手机 vs 允许手机"),
  ],
  EssayCategory.career: [
    PresetTopic(topic: "Working a full-time job vs. Starting one's own business", chineseLabel: "全职工作 vs 自主创业"),
    PresetTopic(topic: "Choosing a high-paying job with high stress vs. A low-paying job with more free time", chineseLabel: "高薪高压 vs 低薪自由"),
    PresetTopic(topic: "Working for a large corporation vs. Working for a small local company", chineseLabel: "大公司 vs 小公司"),
    PresetTopic(topic: "Staying in the same career path vs. Changing careers entirely in mid-life", chineseLabel: "同一职业 vs 中年转行"),
  ],
  EssayCategory.media: [
    PresetTopic(topic: "Watching movies at home (Streaming) vs. Going to a movie theater", chineseLabel: "在家看流媒体 vs 去电影院"),
    PresetTopic(topic: "Reading news from social media vs. Reading news from official websites", chineseLabel: "社交媒体看新闻 vs 官网看新闻"),
    PresetTopic(topic: "Traveling to natural areas (Eco-tourism) vs. Visiting historic big cities", chineseLabel: "自然生态游 vs 历史名城游"),
    PresetTopic(topic: "Living completely without internet for a weekend vs. Staying connected 24/7", chineseLabel: "断网周末 vs 全天联网"),
  ],
};

String _categoryLabel(EssayCategory c) {
  switch (c) {
    case EssayCategory.transportation: return '🚗 交通与公共安全';
    case EssayCategory.technology:     return '💻 科技与数字化';
    case EssayCategory.lifestyle:      return '🏠 日常生活与消费';
    case EssayCategory.school:         return '📚 学校与学习';
    case EssayCategory.career:         return '💼 工作与未来职场';
    case EssayCategory.media:          return '🎬 媒体与娱乐生活';
  }
}

class EssayConfigScreen extends StatefulWidget {
  const EssayConfigScreen({super.key});

  @override
  State<EssayConfigScreen> createState() => _EssayConfigScreenState();
}

class _EssayConfigScreenState extends State<EssayConfigScreen> {
  final _customController = TextEditingController();

  EssayCategory _selectedCategory = EssayCategory.school;
  PresetTopic _selectedPreset = presetTopicsByCategory[EssayCategory.school]!.first;

  String _essayType = 'Comparison';
  String _selectedModel = 'llama70b';

  bool _isGenerating = false;
  String? _resultMarkdown;
  String? _errorMessage;
  String? _savedFilePath;

  final GlobalKey _pdfButtonKey = GlobalKey();

  final List<Map<String, String>> _models = [
    {"value": "llama70b", "label": "Llama 3.3 70B (Groq - ⚡ ~10s)"},
    {"value": "qwen32b", "label": "Qwen 2.5 32B (硅基 - 🚀 ~30s)"},
    {"value": "qwen72b", "label": "Qwen 2.5 72B (硅基 - 🐢 ~60s)"},
  ];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String get _finalTopic {
    final custom = _customController.text.trim();
    if (custom.isNotEmpty) return custom;
    return _selectedPreset.topic;
  }

  String _getModelLabel(String val) {
    for (var m in _models) {
      if (m['value'] == val) return m['label'] ?? val;
    }
    return val;
  }

  String _getLoadingLabel() {
    if (_selectedModel == 'llama70b') return "Invoking Llama-3.3-70B... (~5-15s)";
    if (_selectedModel == 'qwen32b') return "Invoking Qwen-32B... (~15-40s)";
    return "Invoking Qwen-72B... (~30-90s)";
  }

  Future<void> _confirmAndGenerate() async {
    if (_finalTopic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入或选择一个写作话题'), backgroundColor: Colors.orange),
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
            const Text('即将调用 AI 生成作文：', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            _confirmRow('话题', _finalTopic),
            const SizedBox(height: 6),
            _confirmRow('类型', _essayType == 'Comparison' ? '对比文 (Comparison)' : '议论文 (Argumentative)'),
            const SizedBox(height: 6),
            _confirmRow('模型', _getModelLabel(_selectedModel)),
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

    if (confirmed == true) await _generate();
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

  Future<void> _generate() async {
    final provider = context.read<RecordingProvider>();
    setState(() {
      _isGenerating = true;
      _resultMarkdown = null;
      _errorMessage = null;
      _savedFilePath = null;
    });

    try {
      final result = await _tryGenerate(provider);
      final savedPath = await _saveToMarkdown(result);
      setState(() {
        _resultMarkdown = result;
        _savedFilePath = savedPath;
        _isGenerating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(savedPath != null ? '✅ 已自动保存到历史记录' : '⚠️ 生成成功但自动保存失败'),
            backgroundColor: savedPath != null ? Colors.green : Colors.orange,
            action: savedPath != null
                ? SnackBarAction(
                    label: '查看',
                    textColor: Colors.white,
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
        _isGenerating = false;
      });
    }
  }

  Future<String> _tryGenerate(RecordingProvider provider) async {
    try {
      return await provider.generateEssayMatrix(
        _finalTopic,
        essayType: _essayType,
        model: _selectedModel,
      );
    } catch (firstError) {
      debugPrint('[Essay] First attempt failed: $firstError — retrying in 5s...');
      await Future.delayed(const Duration(seconds: 5));
      return await provider.generateEssayMatrix(
        _finalTopic,
        essayType: _essayType,
        model: _selectedModel,
      );
    }
  }

  Future<String?> _saveToMarkdown(String content) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final safeTopic = _finalTopic.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_');
      final filename = "Jeff_Essay_${safeTopic}_$dateStr.md";
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

  Future<void> _exportPdf() async {
    if (_resultMarkdown == null) return;
    try {
      final title = 'Jeff_Essay_${_finalTopic.replaceAll(' ', '_')}.pdf';
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
          "写作助手",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu),
            tooltip: "查看历史记录",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
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
                _buildIntroCard(isDark),
                const SizedBox(height: 24),
                _buildFormCard(isDark),
                const SizedBox(height: 24),
                if (_errorMessage != null) _buildErrorCard(),
                if (_isGenerating) _buildLoadingIndicator(isDark),
                if (_resultMarkdown != null) _buildResultSection(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(bool isDark) {
    return Container(
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
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.psychology_outlined, color: Colors.blueAccent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Cost · Time · Happiness",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "从「成本·时间·幸福感」三个维度展开论述，拒绝空话套话，写出自然的学术短文。",
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600], height: 1.3),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFormCard(bool isDark) {
    return Container(
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
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "写作配置",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _customController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: "灵感输入（可选）",
              hintText: "例如: wearing masks",
              hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 13),
              helperText: "填此框则优先使用，忽略下方预设",
              helperStyle: TextStyle(fontSize: 11, color: isDark ? Colors.grey[600] : Colors.grey[400]),
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

          DropdownButtonFormField<EssayCategory>(
            value: _selectedCategory,
            dropdownColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: "预设分类",
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
            items: EssayCategory.values.map((c) {
              return DropdownMenuItem(value: c, child: Text(_categoryLabel(c)));
            }).toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _selectedCategory = val;
                _selectedPreset = presetTopicsByCategory[val]!.first;
              });
            },
          ),
          const SizedBox(height: 20),

          DropdownButtonFormField<PresetTopic>(
            value: _selectedPreset,
            dropdownColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: "预设话题",
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
            items: presetTopicsByCategory[_selectedCategory]!.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text('${p.topic}  (${p.chineseLabel})', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedPreset = val);
            },
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _buildEssayTypeChip('Comparison', '📊 对比文', isDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEssayTypeChip('Argumentative', '📝 议论文', isDark),
              ),
            ],
          ),
          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            value: _selectedModel,
            dropdownColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
            decoration: InputDecoration(
              labelText: "AI 模型",
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
            items: _models.map((m) {
              return DropdownMenuItem(value: m['value'], child: Text(m['label'] ?? ''));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedModel = val);
            },
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isGenerating ? null : _confirmAndGenerate,
              child: _isGenerating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text("生成中...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    )
                  : const Text("生成作文", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEssayTypeChip(String type, String label, bool isDark) {
    final selected = _essayType == type;
    return GestureDetector(
      onTap: () => setState(() => _essayType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent
              : (isDark ? Colors.white12 : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blueAccent : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
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
          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Column(
          children: [
            const LinearProgressIndicator(color: Colors.blueAccent),
            const SizedBox(height: 16),
            Text(_getLoadingLabel(), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
            const SizedBox(height: 8),
            Text(
              "如超时将自动重试一次，请耐心等待",
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[600] : Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_savedFilePath != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已自动保存到历史记录（可在 History 中查看）',
                    style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "生成结果",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Colors.blueAccent),
                  tooltip: '复制全文',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _resultMarkdown!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 已复制到剪贴板")));
                  },
                ),
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
            border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
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
            builders: {'highlight': HighlightBuilder(context)},
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
