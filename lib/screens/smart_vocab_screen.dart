import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vocab_card.dart';
import '../services/vocab_service.dart';
import '../services/tts_service.dart';
import '../recording_provider.dart';

class SmartVocabScreen extends StatefulWidget {
  final List<VocabCard>? initialCards;
  final String? sourceTitle;

  const SmartVocabScreen({
    super.key,
    this.initialCards,
    this.sourceTitle,
  });

  @override
  State<SmartVocabScreen> createState() => _SmartVocabScreenState();
}

class _SmartVocabScreenState extends State<SmartVocabScreen> with SingleTickerProviderStateMixin {
  int _tabIndex = 0; // 0: 待复习, 1: 全部, 2: 已掌握
  int _cardIndex = 0;
  bool _showBack = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VocabService.instance.loadCards();
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_showBack) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _showBack = !_showBack;
    });
  }

  void _playTTS(String text, BuildContext context) async {
    try {
      final tts = TtsService();
      final provider = context.read<RecordingProvider>();
      await tts.speakEnglish(
        text,
        geminiKey: provider.geminiKey,
        siliconFlowKey: provider.siliconFlowKey,
      );
    } catch (e) {
      if (context.mounted && e.toString().contains('NoHeadphones')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 未检测到耳机 (${e.toString().replaceAll("Exception: ", "")})', style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = VocabService.instance;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final allCards = widget.initialCards ?? service.cards;
        List<VocabCard> displayCards;
        if (_tabIndex == 0) {
          displayCards = allCards.where((c) => !c.isMastered).toList();
        } else if (_tabIndex == 2) {
          displayCards = allCards.where((c) => c.isMastered).toList();
        } else {
          displayCards = allCards;
        }

        if (_cardIndex >= displayCards.length && displayCards.isNotEmpty) {
          _cardIndex = displayCards.length - 1;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.sourceTitle != null ? '提炼卡片: ${widget.sourceTitle}' : '📚 智能学术生词本',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新云端同步',
                onPressed: () => service.loadCards(),
              ),
            ],
          ),
          body: Column(
            children: [
              // 顶部分段 Selector
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2C) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildTabItem(0, '📖 待复习 (${allCards.where((c) => !c.isMastered).length})', isDark),
                    _buildTabItem(1, '🗂️ 全部 (${allCards.length})', isDark),
                    _buildTabItem(2, '✅ 已掌握 (${allCards.where((c) => c.isMastered).length})', isDark),
                  ],
                ),
              ),

              Expanded(
                child: displayCards.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.style_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              '暂无符合条件的生词卡片',
                              style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '在笔记或作文页面点击“✨ 提炼生词与长难句”即可生成！',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // 进度条
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            child: Row(
                              children: [
                                Text(
                                  '卡片 ${_cardIndex + 1} / ${displayCards.length}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Text(
                                  '点击卡片可翻转 🔄',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                                ),
                              ],
                            ),
                          ),

                          // Flip Card 容器
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                              child: GestureDetector(
                                onTap: _flipCard,
                                child: AnimatedBuilder(
                                  animation: _flipAnimation,
                                  builder: (context, child) {
                                    final angle = _flipAnimation.value * pi;
                                    final isBack = angle >= pi / 2;
                                    final currentCard = displayCards[_cardIndex];

                                    return Transform(
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, 0.001)
                                        ..rotateY(angle),
                                      alignment: Alignment.center,
                                      child: isBack
                                          ? Transform(
                                              transform: Matrix4.identity()..rotateY(pi),
                                              alignment: Alignment.center,
                                              child: _buildCardBack(currentCard, isDark),
                                            )
                                          : _buildCardFront(currentCard, isDark),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                          // 底部翻页与掌握按钮控制
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  label: const Text('上一张'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  onPressed: _cardIndex > 0
                                      ? () {
                                          setState(() {
                                            _cardIndex--;
                                            _showBack = false;
                                            _flipController.reset();
                                          });
                                        }
                                      : null,
                                ),
                                ElevatedButton.icon(
                                  icon: Icon(
                                    displayCards[_cardIndex].isMastered
                                        ? Icons.check_circle_rounded
                                        : Icons.check_circle_outline_rounded,
                                    color: displayCards[_cardIndex].isMastered ? Colors.green : null,
                                  ),
                                  label: Text(displayCards[_cardIndex].isMastered ? '已标记掌握' : '标记已掌握'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: displayCards[_cardIndex].isMastered
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.blueAccent.withOpacity(0.1),
                                    foregroundColor: displayCards[_cardIndex].isMastered ? Colors.green : Colors.blueAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  onPressed: () {
                                    final c = displayCards[_cardIndex];
                                    service.saveCard(VocabCard(
                                      id: c.id,
                                      wordOrPhrase: c.wordOrPhrase,
                                      phonetic: c.phonetic,
                                      definition: c.definition,
                                      exampleSentence: c.exampleSentence,
                                      exampleTranslation: c.exampleTranslation,
                                      grammarBreakdown: c.grammarBreakdown,
                                      sourceTitle: c.sourceTitle,
                                      createdAt: c.createdAt,
                                      isMastered: !c.isMastered,
                                    ));
                                  },
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  label: const Text('下一张'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  onPressed: _cardIndex < displayCards.length - 1
                                      ? () {
                                          setState(() {
                                            _cardIndex++;
                                            _showBack = false;
                                            _flipController.reset();
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabItem(int index, String label, bool isDark) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tabIndex = index;
            _cardIndex = 0;
            _showBack = false;
            _flipController.reset();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C3E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardFront(VocabCard card, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.blueAccent.withOpacity(0.3) : Colors.blueAccent.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              card.sourceTitle.isNotEmpty ? card.sourceTitle : '学术考点',
              style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            card.wordOrPhrase,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3),
            textAlign: TextAlign.center,
          ),
          if (card.phonetic != null && card.phonetic!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              card.phonetic!,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.cyanAccent : Colors.teal),
            ),
          ],
          const SizedBox(height: 24),
          IconButton.filled(
            icon: const Icon(Icons.volume_up_rounded),
            iconSize: 28,
            style: IconButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _playTTS(card.wordOrPhrase, context),
          ),
          const SizedBox(height: 20),
          Text(
            '💡 点击卡片查看释义与长难句剖析',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack(VocabCard card, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.tealAccent.withOpacity(0.3) : Colors.teal.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.definition,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.tealAccent : Colors.teal[800],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.blueAccent),
                  onPressed: () => _playTTS(card.exampleSentence.isNotEmpty ? card.exampleSentence : card.wordOrPhrase, context),
                ),
              ],
            ),
            const Divider(height: 24),
            if (card.exampleSentence.isNotEmpty) ...[
              const Text('📝 原文例句:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                card.exampleSentence,
                style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                card.exampleTranslation,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 16),
            ],
            if (card.grammarBreakdown.isNotEmpty) ...[
              const Text('🧐 语法剖析 & 考点:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.2)),
                ),
                child: Text(
                  card.grammarBreakdown,
                  style: TextStyle(fontSize: 12, height: 1.5, color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
