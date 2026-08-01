import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/mindmap_tree_builder.dart';

void main() {
  group('MindmapTreeBuilder', () {
    const sampleShorthand = '''
【30秒理解·可播放】
一位教授介绍从众实验，多数参与者在压力下放弃个人判断。
━━━━━━━━━━━━
【Purpose（目的）】
Introduce a conformity experiment（从众实验）→ demonstrate social pressure.
━━━━━━━━━━━━
【Examples（案例）】
── Facial Line Test（线条判断测试）· 37% error ──
participants matched group answer b/c peer pressure
── Age Correlation Study · 1988 · Stanford ──
older participants ↓ conformity
━━━━━━━━━━━━
【Conclusion（结论）】
Social pressure is a stronger force than personal conviction ✓
━━━━━━━━━━━━
【二听】
?（待核对）exact 37% figure
✓（已确认）no critical gaps
━━━━━━━━━━━━
【符号】
→ 导致/过程/结果｜↑ 提高｜↓ 减少｜＋ 包含｜/ 并列
''';

    test('splits into block headings', () {
      final out = MindmapTreeBuilder.build(shorthand: sampleShorthand);
      expect(out, contains('## 30秒理解·可播放'));
      expect(out, contains('## Purpose（目的）'));
      expect(out, contains('## Examples（案例）'));
      expect(out, contains('## Conclusion（结论）'));
      expect(out, contains('## 二听'));
      expect(out, contains('## 符号'));
    });

    test('keeps body lines as bullets', () {
      final out = MindmapTreeBuilder.build(shorthand: sampleShorthand);
      expect(out, contains('- Introduce a conformity experiment'));
      expect(out, contains('?（待核对）exact 37% figure'));
      expect(out, contains('✓（已确认）no critical gaps'));
    });

    test('handles ── case divisions as nested bullets', () {
      final out = MindmapTreeBuilder.build(shorthand: sampleShorthand);
      expect(
        out,
        contains('- **── Facial Line Test（线条判断测试）· 37% error ──**'),
      );
    });

    test('empty shorthand returns placeholder', () {
      final out = MindmapTreeBuilder.build(shorthand: '');
      expect(out, contains('暂无速记内容'));
    });

    test('fallback builds from transcript lines', () {
      final out = MindmapTreeBuilder.buildFallback(
        title: '思维导图',
        transcriptLines: const [
          {'en': 'The lecture explains an important concept.', 'zh': '这节课解释了一个重要概念。'},
        ],
      );
      expect(out, contains('# 思维导图'));
      expect(out, contains('The lecture explains an important concept.'));
      expect(out, contains('这节课解释了一个重要概念。'));
    });
  });
}
