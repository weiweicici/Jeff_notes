import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../recording_provider.dart';
import 'notes_screen.dart';
import 'essay_config_screen.dart';
import 'history_screen.dart';
import 'smart_vocab_screen.dart';

class AcademicHubScreen extends StatelessWidget {
  const AcademicHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F0F1A),
                    const Color(0xFF161626),
                    const Color(0xFF1E1C2C),
                  ]
                : [
                    const Color(0xFFF7F8FC),
                    const Color(0xFFEEF1F7),
                    const Color(0xFFE5E9F3),
                  ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 20.0,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Title Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Jeff Notes",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "极致双云学术辅助系统",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.history_edu,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              tooltip: "历史记录",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const HistoryScreen(),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.settings_outlined,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              tooltip: "设置",
                              onPressed: () => showAppSettingsDialog(context),
                            ),
                            IconButton(
                              icon: Icon(
                                provider.isDarkMode
                                    ? Icons.wb_sunny_rounded
                                    : Icons.nightlight_round,
                                color: isDark
                                    ? Colors.amberAccent
                                    : Colors.deepPurple,
                              ),
                              onPressed: () {
                                provider.updateSettings(
                                  isDarkMode: !provider.isDarkMode,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // 1. 学术听力同传
                    _buildHubCard(
                      context: context,
                      title: "🎧 学术听力同传",
                      subtitle: "同声传译 × 智能总结",
                      icon: Icons.headphones_rounded,
                      isActive: true,
                      tagText: "核心",
                      gradientColors: isDark
                          ? [const Color(0xFF1F3A60), const Color(0xFF3498DB)]
                          : [const Color(0xFFE8F1F5), const Color(0xFFBEE3F8)],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(
                              name: '/notes-recording',
                            ),
                            builder: (context) => const NotesScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2. 对比作文写作
                    _buildHubCard(
                      context: context,
                      title: "✍️ 对比作文写作",
                      subtitle: "对比论证 × 经典句型",
                      icon: Icons.edit_note_rounded,
                      isActive: true,
                      tagText: "核心",
                      gradientColors: isDark
                          ? [const Color(0xFF1E4D6B), const Color(0xFF00B4DB)]
                          : [const Color(0xFFE0F7FA), const Color(0xFFB2EBF2)],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EssayConfigScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // 3. 智能学术词库
                    _buildHubCard(
                      context: context,
                      title: "📚 智能学术词库",
                      subtitle: "高频考点 × 3D 翻牌复习",
                      icon: Icons.style_rounded,
                      isActive: true,
                      tagText: "提炼",
                      gradientColors: isDark
                          ? [const Color(0xFF5D4037), const Color(0xFFD35400)]
                          : [const Color(0xFFFDEBD0), const Color(0xFFF5CBA7)],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SmartVocabScreen(),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required String tagText,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E1E2F), const Color(0xFF1A1A26)]
              : [Colors.white, const Color(0xFFFAFAFB)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.deepPurpleAccent.withOpacity(0.1),
          highlightColor: Colors.deepPurpleAccent.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Visual Circle Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.last.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 20),
                // Card Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          // Badge status
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tagText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isActive
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
