import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/text_sanitizer.dart';

void main() {
  test('translation cleanup peels nested wrappers and is idempotent', () {
    const wrapped = r'''```markdown
“Translation: translation: 中文翻译：通过 VPN 连接到 RDP，并保留 Windows Server 的真实 $1。”
```''';

    final once = TextSanitizer.cleanTranslation(wrapped);
    expect(once, r'通过 VPN 连接到 RDP，并保留 Windows Server 的真实 $1。');
    expect(TextSanitizer.cleanTranslation(once), once);
  });

  test('translation cleanup removes repeated labels per line only', () {
    expect(
      TextSanitizer.cleanTranslation('翻译结果：第一句。\nTRANSLATION: 中文翻译：第二句。'),
      '第一句。\n第二句。',
    );
    expect(
      TextSanitizer.cleanTranslation('术语 Translation: 必须保留在正文中。'),
      '术语 Translation: 必须保留在正文中。',
    );
  });
}
