import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';

class ShiftCandidate {
  final DateTime date;
  final String startTime;
  final String endTime;

  const ShiftCandidate({
    required this.date,
    required this.startTime,
    required this.endTime,
  });
}

class WorkInput extends StatefulWidget {
  final List<Map<String, dynamic>> workplaces;
  final void Function(List<ShiftCandidate> candidates, int workplaceId) onSaveShiftCandidates;

  const WorkInput({
    super.key,
    required this.workplaces,
    required this.onSaveShiftCandidates,
  });

  @override
  State<WorkInput> createState() => _WorkInputState();
}

class _WorkInputState extends State<WorkInput> {
  static const double _minimumSelectionHeight = 120.0;

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _startDay = 1;
  int? _selectedWorkplaceId;
  bool _isOcrProcessing = false;

  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  double _imageAspectRatio = 1.0;

  double? _selectionStartY;
  double? _selectionEndY;
  String _ocrRawText = '';
  List<ShiftCandidate> _shiftCandidates = [];

  static final RegExp _timePattern = RegExp(r'(?<!\d)(?:[01]?\d|2[0-3])[:.\- ]?[0-5]\d\b');

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('ギャラリーを開く'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
              ListTile(leading: const Icon(Icons.camera_alt), title: const Text('カメラを開く'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 100);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final decoded = image_lib.decodeImage(bytes);
      if (decoded == null) throw Exception('画像を読み込めませんでした');

      setState(() {
        _selectedImagePath = image.path;
        _selectedImageBytes = bytes;
        _imageAspectRatio = decoded.width / decoded.height;
        _selectionStartY = null;
        _selectionEndY = null;
        _ocrRawText = '';
        _shiftCandidates = <ShiftCandidate>[];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像の読み込みに失敗しました: $e')));
      }
    }
  }

  Future<void> _runOcrOnSelection() async {
    if (_selectedImagePath == null || _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先にシフト表画像を選択してください。')));
      return;
    }

    if (_selectionStartY == null || _selectionEndY == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('選択範囲をタップまたはドラッグしてください。')));
      return;
    }

    if (_selectedWorkplaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('勤務先を選択してください。')));
      return;
    }

    setState(() => _isOcrProcessing = true);

    try {
      final decoded = image_lib.decodeImage(_selectedImageBytes!);
      if (decoded == null) throw Exception('画像をデコードできませんでした');

      final previewHeight = (MediaQuery.of(context).size.width / _imageAspectRatio).clamp(180.0, 420.0);
      debugPrint('OCR対象画像 size=${decoded.width}x${decoded.height}, previewHeight=$previewHeight');

      final startY = (_selectionStartY! / previewHeight * decoded.height).round();
      final endY = (_selectionEndY! / previewHeight * decoded.height).round();
      final safeStartY = startY.clamp(0, decoded.height - 1);
      final safeEndY = endY.clamp(1, decoded.height);
      final cropStart = safeStartY < safeEndY ? safeStartY : safeEndY;
      final cropEnd = safeStartY < safeEndY ? safeEndY : safeStartY;
      final maxCropHeight = decoded.height - cropStart;
      final cropHeight = (cropEnd - cropStart).clamp(32, maxCropHeight < 32 ? 32 : maxCropHeight);

      debugPrint('切り出し範囲 cropStart=$cropStart, cropEnd=$cropEnd, cropHeight=$cropHeight, width=${decoded.width}');

      if (decoded.width < 32 || maxCropHeight < 32 || cropHeight < 32 || cropStart < 0 || cropEnd > decoded.height) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('切り出し画像が小さすぎるためOCRできません。選択範囲を広げてください。')),
          );
        }
        return;
      }

      final cropped = image_lib.copyCrop(
        decoded,
        x: 0,
        y: cropStart,
        width: decoded.width,
        height: cropHeight,
      );
      debugPrint('切り出し後 size=${cropped.width}x${cropped.height}');

      if (cropped.width < 32 || cropped.height < 32) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('切り出した画像がMLKitの最小サイズ未満です。')),
          );
        }
        return;
      }

      final croppedBytes = Uint8List.fromList(image_lib.encodeJpg(cropped, quality: 95));
      final tempFile = File('${Directory.systemTemp.path}/shift_crop_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(croppedBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognized = await _textRecognizer.processImage(inputImage);
      final text = recognized.text.trim();
      final times = _extractTimeTokens(text);

      if (times.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OCR結果から時刻を抽出できませんでした。')));
        }
        return;
      }

      final candidates = <ShiftCandidate>[];
      for (var i = 0; i < times.length - 1; i += 2) {
        candidates.add(ShiftCandidate(
          date: DateTime(_selectedMonth.year, _selectedMonth.month, _startDay + (i ~/ 2)),
          startTime: times[i],
          endTime: times[i + 1],
        ));
      }

      setState(() {
        _ocrRawText = text;
        _shiftCandidates = candidates;
      });

      if (mounted) {
        await _showCandidateReviewDialog(candidates);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR処理でエラーが発生しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  List<String> _extractTimeTokens(String text) {
    final matches = _timePattern.allMatches(text).toList();
    final extracted = <String>[];
    for (final match in matches) {
      final token = match.group(0)!.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = token.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          extracted.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
        }
      }
    }
    return extracted;
  }

  Future<void> _showCandidateReviewDialog(List<ShiftCandidate> candidates) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) {
      return AlertDialog(
        title: const Text('OCR候補を確認'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('対象月: ${_selectedMonth.year}年${_selectedMonth.month}月'),
                Text('開始日: $_startDay 日'),
                const SizedBox(height: 8),
                Text('候補件数: ${candidates.length}件'),
                const SizedBox(height: 12),
                ...candidates.map((candidate) => ListTile(dense: true, title: Text('${candidate.date.month}/${candidate.date.day}  ${candidate.startTime} - ${candidate.endTime}'))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('この候補を保存')),
        ],
      );
    });

    if (confirmed == true) {
      widget.onSaveShiftCandidates(candidates, _selectedWorkplaceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('候補を一括保存しました。')));
      }
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxPreviewHeight = 420.0;
    final imageHeight = _selectedImagePath != null ? MediaQuery.of(context).size.width / _imageAspectRatio : 0.0;
    final previewHeight = imageHeight.clamp(180.0, maxPreviewHeight);
    final hasSelection = _selectionStartY != null && _selectionEndY != null;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('シフト表から行を選択', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(initialValue: _selectedMonth.year, decoration: const InputDecoration(labelText: '対象年'), items: List.generate(5, (index) => DateTime.now().year - 1 + index).map((year) => DropdownMenuItem(value: year, child: Text('$year年'))).toList(), onChanged: (year) { if (year == null) return; setState(() => _selectedMonth = DateTime(year, _selectedMonth.month)); })),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<int>(initialValue: _selectedMonth.month, decoration: const InputDecoration(labelText: '対象月'), items: List.generate(12, (index) => index + 1).map((month) => DropdownMenuItem(value: month, child: Text('$month月'))).toList(), onChanged: (month) { if (month == null) return; final safeDay = _startDay > DateTime(_selectedMonth.year, month + 1, 0).day ? DateTime(_selectedMonth.year, month + 1, 0).day : _startDay; setState(() { _selectedMonth = DateTime(_selectedMonth.year, month); _startDay = safeDay; }); })),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(initialValue: _startDay, decoration: const InputDecoration(labelText: '開始日'), items: List.generate(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day, (index) => index + 1).map((day) => DropdownMenuItem(value: day, child: Text('$day日'))).toList(), onChanged: (value) { if (value != null) setState(() => _startDay = value); }),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(initialValue: _selectedWorkplaceId, decoration: const InputDecoration(labelText: '勤務先を選択'), items: widget.workplaces.map((place) => DropdownMenuItem<int>(value: place['id'] as int, child: Text('${place['name']} (¥${place['hourlyWage']})'))).toList(), onChanged: (value) => setState(() => _selectedWorkplaceId = value)),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image), label: const Text('シフト表画像を選択')),
            const SizedBox(height: 12),
            if (_selectedImagePath != null) ...[
              const Text('1行をタップまたはドラッグして選択してください', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, height: previewHeight, child: Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_selectedImagePath!), width: double.infinity, height: previewHeight, fit: BoxFit.contain)),
                Positioned.fill(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final y = details.localPosition.dy.clamp(0.0, previewHeight);
                    setState(() {
                      _selectionStartY = y;
                      _selectionEndY = (y + _minimumSelectionHeight).clamp(0.0, previewHeight);
                    });
                  },
                  onPanStart: (details) {
                    final y = details.localPosition.dy.clamp(0.0, previewHeight);
                    setState(() {
                      _selectionStartY = y;
                      _selectionEndY = (y + _minimumSelectionHeight).clamp(0.0, previewHeight);
                    });
                  },
                  onPanUpdate: (details) {
                    final y = details.localPosition.dy.clamp(0.0, previewHeight);
                    final start = _selectionStartY ?? y;
                    final end = y < start ? start + _minimumSelectionHeight : y;
                    setState(() {
                      _selectionStartY = y < start ? y : start;
                      _selectionEndY = end < start + _minimumSelectionHeight
                          ? start + _minimumSelectionHeight
                          : end;
                    });
                  },
                )),
                if (hasSelection)
                  Positioned(left: 0, right: 0, top: _selectionStartY!.clamp(0.0, previewHeight), height: (_selectionEndY! - _selectionStartY!).abs().clamp(12.0, previewHeight), child: Container(decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.18), border: Border.all(color: Colors.blue, width: 2), borderRadius: BorderRadius.circular(6))))
              ])),
              const SizedBox(height: 8),
              Text(hasSelection ? '選択範囲: ${(_selectionStartY! / previewHeight * 100).toStringAsFixed(1)}% 〜 ${(_selectionEndY! / previewHeight * 100).toStringAsFixed(1)}%' : '選択中の行はありません', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: _isOcrProcessing ? null : _runOcrOnSelection, icon: _isOcrProcessing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.text_fields), label: const Text('選択行をOCRで解析')),
            ],
            const SizedBox(height: 16),
            if (_ocrRawText.isNotEmpty) ...[
              const Text('OCRテキスト', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(12), color: Colors.grey.shade100, child: SelectableText(_ocrRawText)),
            ],
            if (_shiftCandidates.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('生成候補', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._shiftCandidates.map((candidate) => Card(child: ListTile(title: Text('${candidate.date.month}/${candidate.date.day}  ${candidate.startTime} - ${candidate.endTime}')))),
            ],
          ],
        ),
      ),
    );
  }
}
