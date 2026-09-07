import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../data/grammar_content.dart';
import '../models.dart';
import 'supabase_config.dart';

class GrammarRepository {
  /// The teacher-confirmed exam syllabus. Other source units remain in the
  /// bundled data for safe restoration, but are not shown or offered to the
  /// writing generator during this exam-focused period.
  static const Set<String> _examUnitIds = {
    'unit_2',
    'unit_3',
    'unit_4',
    'unit_5',
    'unit_7',
    'unit_8',
    'unit_17',
    'unit_18',
    'unit_19',
    'unit_20',
    'unit_21',
    'unit_22',
    'unit_24',
    'unit_25',
  };

  static String get _tableUrl => '${SupabaseConfig.url}/rest/v1/grammar_units';

  static String get _anonKey => SupabaseConfig.anonKey;

  static List<GrammarPart> Function()? _hardcodedProvider;
  static List<GrammarPart>? _cachedParts;

  static void setHardcodedProvider(List<GrammarPart> Function() provider) {
    _hardcodedProvider = provider;
  }

  /// Supplies deterministic data to widget tests without network or disk I/O.
  static void setCachedPartsForTesting(List<GrammarPart>? parts) {
    _cachedParts = parts;
  }

  /// 三层数据源：0. Supabase → 1. 本地缓存 → 2. 硬编码保底
  static Future<List<GrammarPart>> loadParts() async {
    if (_cachedParts != null) return _examScope(_cachedParts!);

    try {
      final parts = await _fromSupabase();
      if (parts.isNotEmpty) {
        await _cacheToFile(parts);
        _cachedParts = parts;
        return _examScope(parts);
      }
    } catch (_) {}

    try {
      final cached = await _fromCache();
      if (cached.isNotEmpty) {
        _cachedParts = cached;
        return _examScope(cached);
      }
    } catch (_) {}

    final hardcoded = _fromLocalHardcoded();
    _cachedParts = hardcoded;
    return _examScope(hardcoded);
  }

  /// 强制刷新（下拉刷新用）
  static Future<List<GrammarPart>> refresh() async {
    _cachedParts = null;
    return loadParts();
  }

  static Future<List<GrammarPart>> _fromSupabase() async {
    final response = await http
        .get(
          Uri.parse('$_tableUrl?select=*&order=sort_order.asc'),
          headers: {'apikey': _anonKey, 'Authorization': 'Bearer $_anonKey'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200)
      throw Exception('Supabase error: ${response.statusCode}');

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

    return grouped.entries
        .map(
          (e) =>
              GrammarPart(id: e.key, title: partTitles[e.key]!, units: e.value),
        )
        .toList();
  }

  static Future<List<GrammarPart>> _fromCache() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/grammar_units_cache.json');
    if (!file.existsSync()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data
        .map((e) => GrammarPart.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _cacheToFile(List<GrammarPart> parts) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/grammar_units_cache.json');
      await file.writeAsString(
        jsonEncode(parts.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }

  static List<GrammarPart> _fromLocalHardcoded() {
    if (_hardcodedProvider != null) return _hardcodedProvider!();
    throw StateError(
      'Hardcoded grammar content not set. Call setHardcodedProvider during app init.',
    );
  }

  static List<GrammarPart> _examScope(List<GrammarPart> source) {
    final canonicalUnits = <String, GrammarUnit>{
      for (final part in GrammarContent.parts)
        for (final unit in part.units) unit.id: unit,
    };

    return source
        .map((part) {
          final units = part.units
              .where((unit) => _examUnitIds.contains(unit.id))
              // Keep the latest local exam definitions even if an older cloud
              // cache still contains the former conditional-unit mapping.
              .map((unit) => canonicalUnits[unit.id] ?? unit)
              .toList(growable: false);
          return GrammarPart(id: part.id, title: part.title, units: units);
        })
        .where((part) => part.units.isNotEmpty)
        .toList(growable: false);
  }
}
