import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/services/nait_processing_service.dart';

void main() {
  group('NaitProcessingService JSON & Analysis Parser', () {
    const rawValidJson = '''
{
  "mustDo": [
    "Complete Lab 2 by Sunday night",
    "Change network adapter to VMNet4"
  ],
  "lab": [
    "Step 1: Open PowerShell as Admin",
    "Step 2: Run Install-WindowsFeature AD-Domain-Services"
  ],
  "important": [
    "Do NOT reboot while the DC promo wizard is running"
  ],
  "nextClass": [
    "We will cover Group Policy Objects"
  ],
  "technicalPoints": [
    "FSMO roles distribution across domain controllers"
  ],
  "classroomEnglish": [
    {
      "phrase": "leave it at the default",
      "chineseMeaning": "保持默认设置",
      "context": "For the domain functional level, just leave it at the default.",
      "priority": 5,
      "sourceType": "teacher_original",
      "sourceTimestamp": "00:23:10",
      "audioStart": "00:23:04",
      "audioEnd": "00:23:22"
    }
  ],
  "askTeacher": [
    {
      "text": "Should we leave the database path at default?",
      "sourceType": "practice_sentence"
    }
  ],
  "classmateEnglish": [
    {
      "text": "Did your installation finish?",
      "sourceType": "practice_sentence"
    }
  ],
  "teacherMode": {
    "prompt": "Explain DNS forwarders to a peer.",
    "suggestedOpening": "A forwarder is used when your internal DNS server...",
    "targetChunks": ["root hints", "conditional forwarding"]
  }
}
''';

    test('1. Valid JSON parses completely into NaitClassAnalysis', () {
      final analysis = NaitProcessingService.parseAnalysisJson(
        rawValidJson,
        courseId: 'SYSA1010',
        sessionId: '20260902',
        weekNumber: 1,
      );

      expect(analysis.mustDo.length, 2);
      expect(analysis.mustDo.first, 'Complete Lab 2 by Sunday night');
      expect(analysis.lab.length, 2);
      expect(analysis.important.first, contains('Do NOT reboot'));
      expect(analysis.nextClass.first, contains('Group Policy'));
      expect(analysis.technicalPoints.first, contains('FSMO'));

      expect(analysis.classroomEnglish.length, 1);
      final chunk = analysis.classroomEnglish.first;
      expect(chunk.phrase, 'leave it at the default');
      expect(chunk.chineseMeaning, '保持默认设置');
      expect(chunk.priority, 5);
      expect(chunk.sourceType, 'teacher_original');
      expect(chunk.audioStart, const Duration(minutes: 23, seconds: 4));
      expect(chunk.audioEnd, const Duration(minutes: 23, seconds: 22));

      expect(analysis.askTeacher.length, 1);
      expect(analysis.askTeacher.first.sourceType, 'practice_sentence');

      expect(analysis.classmateEnglish.length, 1);
      expect(analysis.classmateEnglish.first.sourceType, 'practice_sentence');

      expect(analysis.teacherMode, isNotNull);
      expect(analysis.teacherMode!.targetChunks, contains('root hints'));
    });

    test('2. JSON inside markdown code fence parses safely', () {
      final fencedJson = '```json\n$rawValidJson\n```';
      final analysis = NaitProcessingService.parseAnalysisJson(
        fencedJson,
        courseId: 'SYSA1010',
        sessionId: '20260902',
        weekNumber: 1,
      );

      expect(analysis.mustDo.length, 2);
      expect(analysis.classroomEnglish.first.phrase, 'leave it at the default');
    });

    test('3. JSON with surrounding conversational noise strips and parses', () {
      final noisyResponse = 'Here is the analysis you requested:\n```json\n$rawValidJson\n```\nHope this helps!';
      final analysis = NaitProcessingService.parseAnalysisJson(
        noisyResponse,
        courseId: 'SYSA1010',
        sessionId: '20260902',
        weekNumber: 1,
      );

      expect(analysis.mustDo.length, 2);
    });

    test('4. Corrupted JSON throws FormatException allowing retry', () {
      const brokenJson = '{"mustDo": ["incomplete...';
      expect(
        () => NaitProcessingService.parseAnalysisJson(brokenJson),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
