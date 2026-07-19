import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import 'supabase_config.dart';

class GrammarRepository {
  static String get _tableUrl => '${SupabaseConfig.url}/rest/v1/grammar_units';

  static String get _anonKey => SupabaseConfig.anonKey;

  static List<GrammarPart> Function()? _hardcodedProvider;
  static List<GrammarPart>? _cachedParts;

  static void setHardcodedProvider(List<GrammarPart> Function() provider) {
    _hardcodedProvider = provider;
  }

  /// 三层数据源：0. Supabase → 1. 本地缓存 → 2. 硬编码保底
  static Future<List<GrammarPart>> loadParts() async {
    if (_cachedParts != null) return _cachedParts!;

    try {
      final parts = await _fromSupabase();
      if (parts.isNotEmpty) {
        await _cacheToFile(parts);
        _cachedParts = parts;
        return parts;
      }
    } catch (_) {}

    try {
      final cached = await _fromCache();
      if (cached.isNotEmpty) {
        _cachedParts = cached;
        return cached;
      }
    } catch (_) {}

    final hardcoded = _fromLocalHardcoded();
    _cachedParts = hardcoded;
    return hardcoded;
  }

  /// 强制刷新（下拉刷新用）
  static Future<List<GrammarPart>> refresh() async {
    _cachedParts = null;
    return loadParts();
  }

  static Future<List<GrammarPart>> _fromSupabase() async {
    final response = await http.get(
      Uri.parse('$_tableUrl?select=*&order=sort_order.asc'),
      headers: {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) throw Exception('Supabase error: ${response.statusCode}');

    final List<dynamic> rows = jsonDecode(response.body);
    if (rows.isEmpty) return [];

    final Map<String, List<GrammarUnit>> grouped = {};
    final Map<String, String> partTitles = {};
    for (final row in rows) {
      final unit = GrammarUnit(
        id: row['id'] as String,
        title: row['title'] as String,
        outcomes: row['outcomes'] as String,
        chart: row['chart'] as String,
        chineseGuide: row['chinese_guide'] as String,
        keyRules: row['key_rules'] as String,
        commonMistakes: row['common_mistakes'] as String,
        vocabulary: row['vocabulary'] as String,
      );
      final partId = row['part_id'] as String;
      grouped.putIfAbsent(partId, () => []);
      grouped[partId]!.add(unit);
      partTitles[partId] = row['part_title'] as String;
    }

    return grouped.entries.map((e) => GrammarPart(
      id: e.key,
      title: partTitles[e.key]!,
      units: e.value,
    )).toList();
  }

  static Future<List<GrammarPart>> _fromCache() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/grammar_units_cache.json');
    if (!file.existsSync()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data.map((e) => GrammarPart.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _cacheToFile(List<GrammarPart> parts) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/grammar_units_cache.json');
      await file.writeAsString(jsonEncode(parts.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  static List<GrammarPart> _fromLocalHardcoded() {
    if (_hardcodedProvider != null) return _hardcodedProvider!();
    throw StateError('Hardcoded grammar content not set. Call setHardcodedProvider during app init.');
  }
}
