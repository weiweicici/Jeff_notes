import 'dart:core';

/// [Architect: Simplified Terminology Strategy]
/// 术语拦截器已简化为直通模式。
/// 
/// 经过多轮测试，LLM（Groq Llama-3.3-70b）在实时字幕场景下
/// 无法稳定保留任何格式的占位符（«T001»、<<T001>>、[T001] 等均会变异）。
/// 
/// 最优解：移除占位符机制，让 LLM 直接翻译原始英文。
/// Llama-3.3-70b 对"Flutter"、"Supabase"等技术词汇的翻译能力已足够优秀。
/// 
/// 如未来需要恢复术语保护，请在此文件中重新实现。
class TerminologyInterceptor {
  // 直通模式：encode 直接返回原文，lookupTable 为空
  static TerminologyResult encode(String rawEnglish) {
    return TerminologyResult(rawEnglish, {});
  }

  // decode 无需操作，直接返回
  static String decode(String translatedChinese, Map<String, String> lookupTable) {
    return translatedChinese;
  }
}

class TerminologyResult {
  final String safeText;
  final Map<String, String> lookupTable;
  TerminologyResult(this.safeText, this.lookupTable);
}
