import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render/pdf_render.dart';
import '../services/ocr_service.dart';
import '../services/supabase_config.dart';

class ReadingSessionScreen extends StatefulWidget {
  const ReadingSessionScreen({super.key});
  @override
  State<ReadingSessionScreen> createState() => _ReadingSessionScreenState();
}

class _ReadingSessionScreenState extends State<ReadingSessionScreen> {
  final List<XFile> _images = [];
  bool _processing = false;
  String _progressText = '';

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() => _images.addAll(picked));
    }
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final pdfPath = result.files.single.path;
    if (pdfPath == null) return;

    setState(() {
      _processing = true;
      _progressText = '正在打开 PDF...';
    });

    try {
      final doc = await PdfDocument.openFile(pdfPath);
      final pageCount = doc.pageCount > 30 ? 30 : doc.pageCount;
      final pageTexts = <String>[];
      final tempDir = await getTemporaryDirectory();

      for (int i = 1; i <= pageCount; i++) {
        if (!mounted) return;
        setState(() => _progressText = '正在识别第 $i/$pageCount 页...');

        final page = await doc.getPage(i);
        final pageImage = await page.render(width: page.width.toInt(), height: page.height.toInt());
        final uiImage = await pageImage.createImageIfNotAvailable();
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        pageImage.dispose();

        final tempFile = File('${tempDir.path}/pdf_page_$i.png');
        await tempFile.writeAsBytes(byteData!.buffer.asUint8List());

        final text = await OcrService.recognizeText(XFile(tempFile.path));
        pageTexts.add(text);
      }
      await doc.dispose();

      final contentMd = pageTexts.join('\n\n---\n\n');
      final title = '阅读_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';

      await SupabaseConfig.client.from('archives').insert({
        'module': 'reading',
        'title': title,
        'content_md': contentMd,
        'file_hash': md5.convert(utf8.encode('${contentMd}_${DateTime.now().microsecondsSinceEpoch}')).toString(),
        'metadata': {'pageCount': pageCount, 'source': 'pdf'},
        'file_size': contentMd.length,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 导入失败: $e')),
      );
      setState(() => _processing = false);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入完成')),
    );
    Navigator.pop(context);
  }

  Future<void> _startOcr() async {
    if (_images.isEmpty) return;
    setState(() {
      _processing = true;
      _progressText = '正在识别第 1/${_images.length} 页...';
    });

    final pageTexts = <String>[];
    for (int i = 0; i < _images.length; i++) {
      if (!mounted) return;
      setState(() => _progressText = '正在识别第 ${i + 1}/${_images.length} 页...');

      final text = await OcrService.recognizeText(_images[i]);
      pageTexts.add(text);
    }

    final contentMd = pageTexts.join('\n\n---\n\n');
    final title = '阅读_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';

    try {
      await SupabaseConfig.client.from('archives').insert({
        'module': 'reading',
        'title': title,
        'content_md': contentMd,
        'file_hash': md5.convert(utf8.encode('${contentMd}_${DateTime.now().microsecondsSinceEpoch}')).toString(),
        'metadata': {'pageCount': _images.length},
        'file_size': contentMd.length,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
      setState(() => _processing = false);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入完成')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入截图'),
        actions: [
          if (_images.isNotEmpty)
            TextButton(
              onPressed: _processing ? null : _startOcr,
              child: const Text('开始识别'),
            ),
        ],
      ),
      body: _processing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(_progressText, style: const TextStyle(fontSize: 18)),
                ],
              ),
            )
          : _images.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _pickImages,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('从相册选择截图'),
                        ),
                        const SizedBox(height: 12),
                        const Text('支持多选，可拖动排序', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        const Text('— 或者 —', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _processing ? null : _importPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('导入 PDF（至高 30 页）'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text('共 ${_images.length} 张截图', style: const TextStyle(fontSize: 16)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _pickImages,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _images.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = _images.removeAt(oldIndex);
                            _images.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final image = _images[index];
                          return Card(
                            key: ValueKey(image.path),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(image.path),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              title: Text('第 ${index + 1} 页'),
                              subtitle: Text(File(image.path).lengthSync() > 0
                                  ? '${(File(image.path).lengthSync() / 1024).toStringAsFixed(0)} KB'
                                  : ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() => _images.removeAt(index)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
