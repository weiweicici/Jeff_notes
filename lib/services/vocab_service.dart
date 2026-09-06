import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vocab_card.dart';
import 'supabase_config.dart';
import 'cloud_identity_guard.dart';

class VocabService extends ChangeNotifier {
  static VocabService? _instance;
  final List<VocabCard> _cards = [];

  List<VocabCard> get cards => List.unmodifiable(_cards);
  List<VocabCard> get unmasteredCards =>
      _cards.where((c) => !c.isMastered).toList();
  List<VocabCard> get masteredCards =>
      _cards.where((c) => c.isMastered).toList();

  VocabService._();

  static VocabService get instance {
    _instance ??= VocabService._();
    return _instance!;
  }

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/vocab_cards.json');
  }

  Future<void> loadCards() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final rawList = jsonDecode(content) as List;
        _cards.clear();
        for (final item in rawList) {
          _cards.add(VocabCard.fromJson(item as Map<String, dynamic>));
        }
      }
      notifyListeners();
      _syncFromSupabase();
    } catch (e) {
      debugPrint('[VocabService Load Error] $e');
    }
  }

  Future<void> saveCard(VocabCard card) async {
    final existingIdx = _cards.indexWhere(
      (c) =>
          c.id == card.id ||
          c.wordOrPhrase.toLowerCase() == card.wordOrPhrase.toLowerCase(),
    );
    if (existingIdx != -1) {
      _cards[existingIdx] = card;
    } else {
      _cards.insert(0, card);
    }
    await _persistLocal();
    notifyListeners();
    _uploadToSupabase(card);
  }

  Future<void> deleteCard(String id) async {
    _cards.removeWhere((c) => c.id == id);
    await _persistLocal();
    notifyListeners();
    // [BUG-04 Fix] 同步删除 Supabase 云端记录，防止词卡重启后复活
    _deleteFromSupabase(id);
  }

  Future<void> toggleMastered(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _cards[idx].isMastered = !_cards[idx].isMastered;
      await _persistLocal();
      notifyListeners();
      // [BUG-05 Fix] 同步已掌握状态到云端，不能只写到本地
      _uploadToSupabase(_cards[idx]);
    }
  }

  Future<void> _persistLocal() async {
    try {
      final file = await _localFile;
      final raw = jsonEncode(_cards.map((c) => c.toJson()).toList());
      await file.writeAsString(raw);
    } catch (e) {
      debugPrint('[VocabService Persist Error] $e');
    }
  }

  Future<void> _uploadToSupabase(VocabCard card) async {
    try {
      final userId = CloudIdentityGuard.capture();
      if (userId == null || !CloudIdentityGuard.stillCurrent(userId)) return;
      // [BUG-05 Fix] 使用 upsert 而非 insert，防止重复行积累（on_conflict: file_hash）
      await SupabaseConfig.client.from('archives').upsert({
        'file_hash': 'vocab_${card.id}',
        'module': 'vocab',
        'title': 'VocabCard: ${card.wordOrPhrase}',
        'content_md': jsonEncode(card.toJson()),
        'file_size': card.wordOrPhrase.length,
        'user_id': userId,
      }, onConflict: 'file_hash');
      debugPrint('[Vocab Cloud Upsert OK] ${card.wordOrPhrase}');
    } catch (e) {
      debugPrint('[Vocab Cloud Upload Error] $e');
    }
  }

  /// [BUG-04 Fix] 删除 Supabase 中对应词卡记录
  Future<void> _deleteFromSupabase(String id) async {
    try {
      final userId = CloudIdentityGuard.capture();
      if (userId == null || !CloudIdentityGuard.stillCurrent(userId)) return;
      await SupabaseConfig.client
          .from('archives')
          .delete()
          .eq('file_hash', 'vocab_$id')
          .eq('user_id', userId);
      debugPrint('[Vocab Cloud Delete OK] vocab_$id');
    } catch (e) {
      debugPrint('[Vocab Cloud Delete Error] $e');
    }
  }

  Future<void> _syncFromSupabase() async {
    try {
      final userId = SupabaseConfig.currentUserId;
      if (userId == null) return;
      final data = await SupabaseConfig.client
          .from('archives')
          .select('content_md')
          .eq('module', 'vocab')
          .eq('user_id', userId);
      if (!CloudIdentityGuard.stillCurrent(userId)) return;
      for (final row in List<Map<String, dynamic>>.from(data as List)) {
        final contentStr = row['content_md'] as String?;
        if (contentStr != null && contentStr.isNotEmpty) {
          try {
            final card = VocabCard.decode(contentStr);
            if (!_cards.any(
              (c) =>
                  c.id == card.id ||
                  c.wordOrPhrase.toLowerCase() ==
                      card.wordOrPhrase.toLowerCase(),
            )) {
              _cards.add(card);
            }
          } catch (_) {}
        }
      }
      await _persistLocal();
      notifyListeners();
    } catch (e) {
      debugPrint('[Vocab Cloud Sync Error] $e');
    }
  }
}
