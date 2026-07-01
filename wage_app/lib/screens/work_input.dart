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

class _SelectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.withValues(alpha: 0.18);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.blue;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WorkInputState extends State<WorkInput> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _startDay = 1;
  int? _selectedWorkplaceId;
  bool _isOcrProcessing = false;

  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  double _imageAspectRatio = 1.0;
  double _viewerScale = 1.0;

  Rect _selectedRect = Rect.zero;
  Offset? _selectionStart;
  String _ocrRawText = '';
  List<ShiftCandidate> _shiftCandidates = [];
  List<Map<String, dynamic>> _ocrDebugEntries = [];
  Uint8List? _debugCropBytes;

  static final RegExp _timePattern = RegExp(r'([01]?\d|2[0-3])[:：.]([0-5]\d)');

  Rect _normalizeRect(Rect rect) {
    final left = rect.left < rect.right ? rect.left : rect.right;
    final top = rect.top < rect.bottom ? rect.top : rect.bottom;
    final right = rect.left < rect.right ? rect.right : rect.left;
    final bottom = rect.top < rect.bottom ? rect.bottom : rect.top;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ===== Added =====
  Rect _constrainRect(Rect rect, double maxWidth, double maxHeight) {
    final normalized = _normalizeRect(rect);
    final left = normalized.left.clamp(0.0, maxWidth);
    final top = normalized.top.clamp(0.0, maxHeight);
    final right = normalized.right.clamp(0.0, maxWidth);
    final bottom = normalized.bottom.clamp(0.0, maxHeight);
    return _normalizeRect(Rect.fromLTRB(left, top, right, bottom));
  }

  Rect _buildSelectionRect(Offset start, Offset end, double maxWidth, double maxHeight) {
    return _constrainRect(Rect.fromPoints(start, end), maxWidth, maxHeight);
  }

  void _startSelection(Offset localPosition, double maxWidth, double maxHeight) {
    setState(() {
      _selectionStart = Offset(localPosition.dx.clamp(0.0, maxWidth), localPosition.dy.clamp(0.0, maxHeight));
      _selectedRect = Rect.fromLTWH(_selectionStart!.dx, _selectionStart!.dy, 1.0, 1.0);
    });
  }

  image_lib.Image _cropRow(image_lib.Image image, Rect rowRect) {
    return image_lib.copyCrop(
      image,
      x: rowRect.left.toInt(),
      y: rowRect.top.toInt(),
      width: rowRect.width.toInt().clamp(32, image.width),
      height: rowRect.height.toInt().clamp(32, image.height),
    );
  }

  List<Rect> _splitColumns(image_lib.Image image, int columnCount) {
    final columns = <Rect>[];
    for (var index = 0; index < columnCount; index++) {
      final startX = (index * image.width / columnCount).floor();
      final endX = index + 1 == columnCount ? image.width : ((index + 1) * image.width / columnCount).floor();
      if (endX <= startX) {
        continue;
      }
      columns.add(Rect.fromLTWH(startX.toDouble(), 0, (endX - startX).toDouble(), image.height.toDouble()));
    }
    return columns;
  }

  Future<Map<String, dynamic>> _processColumn(image_lib.Image rowImage, Rect columnRect, int day) async {
    final columnImage = image_lib.copyCrop(
      rowImage,
      x: columnRect.left.toInt(),
      y: columnRect.top.toInt(),
      width: columnRect.width.toInt().clamp(32, rowImage.width),
      height: columnRect.height.toInt().clamp(32, rowImage.height),
    );
    final columnBytes = Uint8List.fromList(image_lib.encodeJpg(columnImage, quality: 95));
    final tempColumnFile = File('${Directory.systemTemp.path}/shift_column_${day}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempColumnFile.writeAsBytes(columnBytes);

    final inputImage = InputImage.fromFilePath(tempColumnFile.path);
    final recognized = await _textRecognizer.processImage(inputImage);
    final extractedTimes = _extractTimeTokens(recognized.text.trim());
    final dedupedTimes = _dedupeConsecutiveTimes(extractedTimes);

    String startTime = '休';
    String endTime = '休';
    if (dedupedTimes.length >= 2) {
      startTime = _formatTime(dedupedTimes.first);
      endTime = _formatTime(dedupedTimes.last);
    }

    return {
      'day': day,
      'ocrText': recognized.text.trim(),
      'extractedTimes': dedupedTimes,
      'startTime': startTime,
      'endTime': endTime,
      'selectedText': startTime == '休' ? '休み' : '$startTime-$endTime',
      'columnBytes': columnBytes,
    };
  }

  void _showDebugCrop(Uint8List cropBytes) {
    if (mounted) {
      setState(() => _debugCropBytes = cropBytes);
    }
  }

  bool _isRestCandidate(ShiftCandidate candidate) {
    return candidate.startTime == '休' && candidate.endTime == '休';
  }
  // ===== End Added =====

  // ===== End Added =====

  List<String> _dedupeConsecutiveTimes(List<String> times) {
    final result = <String>[];
    for (final time in times) {
      if (result.isEmpty || result.last != time) {
        result.add(time);
      }
    }
    return result;
  }

  int _durationHours(String start, String end) {
    final startMinutes = _toMinutes(start);
    final endMinutes = _toMinutes(end);
    final adjustedEnd = endMinutes < startMinutes ? endMinutes + 24 * 60 : endMinutes;
    return ((adjustedEnd - startMinutes) / 60).round();
  }

  int _toMinutes(String time) {
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

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
        _selectedRect = Rect.zero;
        _selectionStart = null;
        _ocrRawText = '';
        _shiftCandidates = <ShiftCandidate>[];
        _ocrDebugEntries = <Map<String, dynamic>>[];
        _debugCropBytes = null;
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

    final rect = _normalizeRect(_selectedRect);
    if (rect.width <= 0 || rect.height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('行をタップしてOCR対象を指定してください。')));
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

      final previewWidth = MediaQuery.of(context).size.width - 32.0;
      final previewHeight = (previewWidth / _imageAspectRatio).clamp(180.0, 420.0);
      final visibleWidth = previewWidth * _viewerScale;
      final visibleHeight = previewHeight * _viewerScale;
      final scaleX = visibleWidth > 0 ? decoded.width / visibleWidth : 1.0;
      final scaleY = visibleHeight > 0 ? decoded.height / visibleHeight : 1.0;
      final cropRect = Rect.fromLTRB(
        (rect.left * scaleX).round().clamp(0, decoded.width - 1).toDouble(),
        (rect.top * scaleY).round().clamp(0, decoded.height - 1).toDouble(),
        (rect.right * scaleX).round().clamp(1, decoded.width).toDouble(),
        (rect.bottom * scaleY).round().clamp(1, decoded.height).toDouble(),
      );

      final cropped = _cropRow(decoded, cropRect);
      final croppedBytes = Uint8List.fromList(image_lib.encodeJpg(cropped, quality: 95));
      _showDebugCrop(croppedBytes);

      final daysInMonth = DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);
      final debugEntries = <Map<String, dynamic>>[];
      final candidates = <ShiftCandidate>[];
      final rowColumns = _splitColumns(cropped, daysInMonth);

      for (var index = 0; index < rowColumns.length; index++) {
        final day = index + 1;
        final columnResult = await _processColumn(cropped, rowColumns[index], day);
        debugEntries.add(columnResult);

        final startTime = columnResult['startTime'] as String;
        final endTime = columnResult['endTime'] as String;
        final dayNumber = (_startDay - 1 + day).clamp(1, daysInMonth);
        if (startTime != '休') {
          candidates.add(ShiftCandidate(
            date: DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber),
            startTime: startTime,
            endTime: endTime,
          ));
        } else {
          candidates.add(ShiftCandidate(
            date: DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber),
            startTime: '休',
            endTime: '休',
          ));
        }
      }

      setState(() {
        _ocrRawText = debugEntries.map((entry) => '【${entry['day']}日】${entry['ocrText']}').join('\n');
        _shiftCandidates = candidates;
        _ocrDebugEntries = debugEntries;
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
    final extracted = <String>[];
    for (final match in _timePattern.allMatches(text)) {
      final hour = int.tryParse(match.group(1)!);
      final minute = int.tryParse(match.group(2)!);
      if (hour != null && minute != null) {
        extracted.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
      }
    }
    return extracted;
  }

  String _formatCandidateLabel(ShiftCandidate candidate) {
    if (_isRestCandidate(candidate)) {
      return '${candidate.date.month}/${candidate.date.day}  休み';
    }
    return '${candidate.date.month}/${candidate.date.day}  ${candidate.startTime} - ${candidate.endTime}';
  }

  Future<void> _showCandidateReviewDialog(List<ShiftCandidate> candidates) async {
    final selected = List<bool>.filled(candidates.length, true);
    final editableCandidates = List<ShiftCandidate>.from(candidates);

    final confirmed = await showDialog<bool>(context: context, builder: (context) {
      return AlertDialog(
        title: const Text('OCR候補を確認'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(builder: (context, setDialogState) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('対象月: ${_selectedMonth.year}年${_selectedMonth.month}月'),
                  Text('開始日: $_startDay 日'),
                  const SizedBox(height: 8),
                  Text('候補件数: ${editableCandidates.length}件'),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  const Text('採用候補', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...List.generate(editableCandidates.length, (index) {
                    final candidate = editableCandidates[index];
                    return ListTile(
                      leading: Checkbox(
                        value: selected[index],
                        onChanged: (value) => setDialogState(() => selected[index] = value ?? false),
                      ),
                      title: Text(_formatCandidateLabel(candidate)),
                      subtitle: _durationHours(candidate.startTime, candidate.endTime) >= 12
                          ? const Text('夜勤候補として判定されました。OCR誤認識の可能性があります。')
                          : null,
                      onTap: () async {
                        final edited = await _editCandidate(candidate);
                        if (edited != null) {
                          editableCandidates[index] = edited;
                          setDialogState(() {});
                        }
                      },
                    );
                  }),
                ],
              ),
            );
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      );
    });

    if (confirmed == true) {
      final saved = <ShiftCandidate>[];
      for (var i = 0; i < editableCandidates.length; i++) {
        if (selected[i] && !_isRestCandidate(editableCandidates[i])) {
          saved.add(editableCandidates[i]);
        }
      }
      widget.onSaveShiftCandidates(saved, _selectedWorkplaceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('チェックした候補を保存しました: ${saved.length}件')));
      }
    }
  }

  Future<ShiftCandidate?> _editCandidate(ShiftCandidate candidate) async {
    final startController = TextEditingController(text: candidate.startTime);
    final endController = TextEditingController(text: candidate.endTime);

    final result = await showDialog<ShiftCandidate?>(context: context, builder: (context) {
      return AlertDialog(
        title: const Text('候補を編集'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: startController, decoration: const InputDecoration(labelText: '開始時刻 (HH:mm)')),
          const SizedBox(height: 8),
          TextField(controller: endController, decoration: const InputDecoration(labelText: '終了時刻 (HH:mm)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, ShiftCandidate(date: candidate.date, startTime: _formatTime(startController.text), endTime: _formatTime(endController.text))), child: const Text('保存')),
        ],
      );
    });

    startController.dispose();
    endController.dispose();
    return result;
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
    final hasSelection = _selectedRect.width > 0 && _selectedRect.height > 0;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('シフト表の行を選択', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const Text(
                '画像上をドラッグしてOCR対象の矩形を指定してください',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: previewHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final previewHeightForLayout = (availableWidth / _imageAspectRatio).clamp(180.0, 420.0);
                    final hasSelection = _selectedRect.width > 0 && _selectedRect.height > 0;

                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(8),
                      onInteractionUpdate: (details) {
                        setState(() => _viewerScale = details.scale.clamp(1.0, 4.0));
                      },
                      child: Stack(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (details) {
                              final localPosition = details.localPosition;
                              _startSelection(Offset(localPosition.dx, localPosition.dy), availableWidth, previewHeightForLayout);
                            },
                            onPanUpdate: (details) {
                              if (_selectionStart == null) return;
                              final localPosition = details.localPosition;
                              setState(() {
                                _selectedRect = _buildSelectionRect(
                                  _selectionStart!,
                                  Offset(localPosition.dx.clamp(0.0, availableWidth), localPosition.dy.clamp(0.0, previewHeightForLayout)),
                                  availableWidth,
                                  previewHeightForLayout,
                                );
                              });
                            },
                            onPanEnd: (_) {
                              setState(() => _selectionStart = null);
                            },
                            onTapDown: (details) {
                              final localPosition = details.localPosition;
                              _startSelection(Offset(localPosition.dx, localPosition.dy), availableWidth, previewHeightForLayout);
                            },
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(_selectedImagePath!), width: availableWidth, height: previewHeightForLayout, fit: BoxFit.contain),
                                ),
                                if (hasSelection)
                                  Positioned(
                                    left: _selectedRect.left,
                                    top: _selectedRect.top,
                                    width: _selectedRect.width.clamp(1.0, availableWidth),
                                    height: _selectedRect.height.clamp(1.0, previewHeightForLayout),
                                    child: CustomPaint(
                                      painter: _SelectionPainter(),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSelection
                    ? '選択行: Y ${_selectedRect.top.toStringAsFixed(1)}〜${_selectedRect.bottom.toStringAsFixed(1)} / 高さ ${_selectedRect.height.toStringAsFixed(1)}px'
                    : '行を選択してください',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                _ocrRawText.isEmpty
                    ? 'OCR結果: 未実行'
                    : 'OCR結果: ${_shiftCandidates.length}件の候補を検出済み',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (_debugCropBytes != null) ...[
                const SizedBox(height: 12),
                const Text('【OCR対象画像】', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  height: 180,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                  child: ClipRRect(
                    child: Image.memory(_debugCropBytes!, fit: BoxFit.contain),
                  ),
                ),
              ],
              if (_ocrDebugEntries.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('OCRデバッグ', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...List.generate(_ocrDebugEntries.length, (index) {
                  final entry = _ocrDebugEntries[index];
                  final day = entry['day'] as int;
                  final extractedTimes = entry['extractedTimes'] as List<String>;
                  final selectedText = entry['selectedText'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$day日', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('OCR: ${entry['ocrText'].toString().isEmpty ? 'なし' : entry['ocrText']}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(extractedTimes.isEmpty ? '勤務なし' : '開始${extractedTimes.first} / 終了${extractedTimes.last}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('採用: $selectedText', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: hasSelection && !_isOcrProcessing ? _runOcrOnSelection : null,
                icon: _isOcrProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.text_fields),
                label: Text(_isOcrProcessing ? 'OCR実行中...' : 'この行でOCR実行'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
