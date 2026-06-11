import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../recording_provider.dart';
import 'notes_screen.dart';

class AcademicHubScreen extends StatelessWidget {
  const AcademicHubScreen({super.key});

  void _showBetaSheet(BuildContext context, String title, String featureName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -5),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.science_outlined,
                    color: Colors.deepPurpleAccent,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "“$featureName” 模块正在基于 SiliconFlow Qwen-72B 的学术论证与硬核句式重塑能力进行高精度的私有化对齐与模板微调，敬请期待！",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "收到",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
                ? [const Color(0xFF0F0F1A), const Color(0xFF161626), const Color(0xFF1E1C2C)]
                : [const Color(0xFFF7F8FC), const Color(0xFFEEF1F7), const Color(0xFFE5E9F3)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
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
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        // Dark Mode Toggle
                        IconButton(
                          icon: Icon(
                            provider.isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                            color: isDark ? Colors.amberAccent : Colors.deepPurple,
                          ),
                          onPressed: () {
                            provider.updateSettings(isDarkMode: !provider.isDarkMode);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    
                    // Card 1: Listening
                    _buildHubCard(
                      context: context,
                      title: "学术听力同传总结",
                      subtitle: "Groq × Qwen 72B 实时提取考点",
                      icon: Icons.headphones_rounded,
                      isActive: true,
                      tagText: "ACTIVE",
                      gradientColors: isDark
                          ? [const Color(0xFF2C3E50), const Color(0xFF3498DB)]
                          : [const Color(0xFFECF0F1), const Color(0xFFBDC3C7)],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const NotesScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Card 2: Essay
                    _buildHubCard(
                      context: context,
                      title: "论文逻辑重构",
                      subtitle: "因果论证钢性模板检测",
                      icon: Icons.analytics_rounded,
                      isActive: false,
                      tagText: "BETA",
                      gradientColors: isDark
                          ? [const Color(0xFF8E44AD), const Color(0xFF9B59B6)]
                          : [const Color(0xFFE8DAEF), const Color(0xFFD2B4DE)],
                      onTap: () => _showBetaSheet(context, "论文逻辑重构", "论文逻辑重构"),
                    ),
                    const SizedBox(height: 20),

                    // Card 3: Grammar
                    _buildHubCard(
                      context: context,
                      title: "硬核语法语法糖",
                      subtitle: "高阶学术词汇平替",
                      icon: Icons.spellcheck_rounded,
                      isActive: false,
                      tagText: "BETA",
                      gradientColors: isDark
                          ? [const Color(0xFFD35400), const Color(0xFFE67E22)]
                          : [const Color(0xFFFDEBD0), const Color(0xFFF5CBA7)],
                      onTap: () => _showBetaSheet(context, "硬核语法语法糖", "高阶学术词汇平替"),
                    ),
                  ]),
                ),
              )
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
          )
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
                      )
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                color: isActive ? Colors.greenAccent : Colors.orangeAccent,
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
