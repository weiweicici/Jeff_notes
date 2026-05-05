import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService(String apiKey)
      : _model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: apiKey,
        );

  Future<Map<String, dynamic>> processAudioChunk(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      final prompt = [
        Content.multi([
          TextPart(
              "你是一个课堂笔记助手。请分析这段 30 秒的音频。必须返回 JSON 格式，包含两个键：'summary'（精炼的一句话总结）和 'transcript'（详细的内容转录）。严禁返回 JSON 以外的任何文字。"),
          DataPart('audio/mp4', bytes),
        ])
      ];

      debugPrint('AI Request Sent: ${filePath.split('/').last}');
      
      final response = await _model
          .generateContent(prompt)
          .timeout(const Duration(seconds: 20), onTimeout: () {
        throw Exception("Gemini API request timed out after 20 seconds.");
      });

      final text = response.text;
      debugPrint('AI Response Received: $text');

      if (text == null) {
        throw Exception("Gemini returned null response");
      }

      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
      if (jsonMatch == null) {
        debugPrint('JSON Parse Failed. Raw Text: $text');
        throw Exception("Could not find JSON in Gemini response");
      }

      final jsonString = jsonMatch.group(0)!;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('GeminiService Error: $e');
      rethrow;
    }
  }
}
