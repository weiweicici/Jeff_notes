import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrService {
  static Future<String> recognizeText(XFile image) async {
    final inputImage = InputImage.fromFile(File(image.path));
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(inputImage);
      return result.text;
    } finally {
      recognizer.close();
    }
  }

  static Future<List<String>> recognizeBatch(List<XFile> images) async {
    final results = <String>[];
    for (int i = 0; i < images.length; i++) {
      final text = await recognizeText(images[i]);
      results.add(text);
    }
    return results;
  }
}
