/// 种子脚本 — 将 grammar_content.dart 全部数据推送到 Supabase grammar_units 表
///
/// 用法:
///   1. 先确认 grammar_units 表已创建（在 Supabase SQL Editor 执行 create_grammar_units.sql）
///   2. cd jeff_notes && dart run scripts/seed_grammar_units.dart
///
/// 注意: RLS 已禁用，使用 anon key 即可写入

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lib/data/grammar_content.dart';

const String _supabaseUrl = 'https://cplqrewuoltiechxxtjk.supabase.co';
const String _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwbHFyZXd1b2x0aWVjaHh4dGprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwNDg0MDMsImV4cCI6MjA5NjYyNDQwM30.iDypdQt1RpcpffUvtrg_Ykr2tJwdG3CasoHmruTbS-A';

Future<void> main() async {
  final url = Uri.parse('$_supabaseUrl/rest/v1/grammar_units');
  final headers = {
    'apikey': _anonKey,
    'Authorization': 'Bearer $_anonKey',
    'Content-Type': 'application/json',
    'Prefer': 'resolution=merge-duplicates',
  };

  int total = 0;
  for (final part in GrammarContent.parts) {
    int sortOrder = 0;
    for (final unit in part.units) {
      sortOrder++;
      final body = {
        'id': unit.id,
        'part_id': part.id,
        'part_title': part.title,
        'title': unit.title,
        'outcomes': unit.outcomes,
        'chart': unit.chart,
        'chinese_guide': unit.chineseGuide,
        'key_rules': unit.keyRules,
        'common_mistakes': unit.commonMistakes,
        'vocabulary': unit.vocabulary,
        'sort_order': sortOrder,
      };

      final response = await http.post(url, headers: headers, body: jsonEncode(body));
      if (response.statusCode == 201 || response.statusCode == 200) {
        total++;
        print('✓ ${unit.id} — ${unit.title}');
      } else {
        print('✗ ${unit.id}: ${response.statusCode} ${response.body}');
      }
    }
  }

  print('\n完成: 共写入 $total 条记录');
}
