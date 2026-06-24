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
  static const double _minimumSelectionHeight = 36.0;

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
  String _ocrRawText = '';
  List<ShiftCandidate> _shiftCandidates = [];

  static final RegExp _timePattern = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

  Rect _normalizeRect(Rect rect) {
    final left = rect.left < rect.right ? rect.left : rect.right;
    final top = rect.top < rect.bottom ? rect.top : rect.bottom;
    final right = rect.left < rect.right ? rect.right : rect.left;
    final bottom = rect.top < rect.bottom ? rect.bottom : rect.top;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  List<String> _dedupeConsecutiveTimes(List<String> times) {
    final result = <String>[];
    for (final time in times) {
      if (result.isEmpty || result.last != time) {
        result.add(time);
      }
    }
    return result;
  }

  List<(String start, String end)> _pairTimesInOrder(List<String> times) {
    final pairs = <(String start, String end)>[];
    for (var i = 0; i + 1 < times.length; i += 2) {
      pairs.add((times[i], times[i + 1]));
    }
    return pairs;
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

    final rect = _normalizeRect(_selectedRect);
    if (rect.width <= 0 || rect.height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('矩形選択範囲を指定してください。')));
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
      final cropStartX = cropRect.left.toInt();
      final cropEndX = cropRect.right.toInt();
      final cropStartY = cropRect.top.toInt();
      final cropEndY = cropRect.bottom.toInt();
      final cropWidth = (cropEndX - cropStartX).clamp(32, decoded.width - cropStartX);
      final cropHeight = (cropEndY - cropStartY).clamp(32, decoded.height - cropStartY);

      debugPrint('OCR対象画像 size=${decoded.width}x${decoded.height}, preview=${previewWidth.toStringAsFixed(1)}x${previewHeight.toStringAsFixed(1)}, scale=$_viewerScale, rect=($cropStartX,$cropStartY,$cropWidth,$cropHeight)');

      if (decoded.width < 32 || decoded.height < 32 || cropWidth < 32 || cropHeight < 32 || cropStartX < 0 || cropEndX > decoded.width || cropStartY < 0 || cropEndY > decoded.height) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('切り出し画像が小さすぎるためOCRできません。選択範囲を広げてください。')),
          );
        }
        return;
      }

      final cropped = image_lib.copyCrop(
        decoded,
        x: cropStartX,
        y: cropStartY,
        width: cropWidth,
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
      final dedupedTimes = _dedupeConsecutiveTimes(times);
      final pairs = _pairTimesInOrder(dedupedTimes);


      if (dedupedTimes.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OCR結果から時刻を抽出できませんでした。')));
        }
        return;
      }

      final candidates = <ShiftCandidate>[];
      for (var i = 0; i < pairs.length; i++) {
        final pair = pairs[i];
        final startTime = _formatTime(pair.$1);
        final endTime = _formatTime(pair.$2);
        if (startTime == endTime) {
          continue;
        }

        final startMinutes = _toMinutes(startTime);
        final endMinutes = _toMinutes(endTime);
        final normalizedEndMinutes = endMinutes < startMinutes ? endMinutes + 24 * 60 : endMinutes;
        final duration = ((normalizedEndMinutes - startMinutes) / 60).round();

        if (duration < 1) {
          continue;
        }
        if (duration > 16) {
          continue;
        }

        final candidate = ShiftCandidate(
          date: DateTime(_selectedMonth.year, _selectedMonth.month, _startDay + i),
          startTime: startTime,
          endTime: endTime,
        );
        candidates.add(candidate);
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
                      title: Text('${candidate.date.month}/${candidate.date.day}  ${candidate.startTime} - ${candidate.endTime}'),
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
        if (selected[i]) saved.add(editableCandidates[i]);
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
            const Text('シフト表から矩形を選択', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const Text('矩形をドラッグしてOCR対象範囲を指定してください', style: TextStyle(color: Colors.grey)),
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(_selectedImagePath!), width: availableWidth, height: previewHeightForLayout, fit: BoxFit.contain),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                final x = details.localPosition.dx.clamp(0.0, availableWidth);
                                final y = details.localPosition.dy.clamp(0.0, previewHeightForLayout);
                                final width = (availableWidth * 0.35).clamp(80.0, availableWidth);
                                setState(() {
                                  _selectedRect = Rect.fromLTWH(x, y, width, _minimumSelectionHeight);
                                });
                              },
                              onPanStart: (details) {
                                final x = details.localPosition.dx.clamp(0.0, availableWidth);
                                final y = details.localPosition.dy.clamp(0.0, previewHeightForLayout);
                                final width = (availableWidth * 0.35).clamp(80.0, availableWidth);
                                setState(() {
                                  _selectedRect = Rect.fromLTWH(x, y, width, _minimumSelectionHeight);
                                });
                              },
                              onPanUpdate: (details) {
                                final x = details.localPosition.dx.clamp(0.0, availableWidth);
                                final y = details.localPosition.dy.clamp(0.0, previewHeightForLayout);
                                setState(() {
                                  _selectedRect = _normalizeRect(Rect.fromLTRB(_selectedRect.left, _selectedRect.top, x, y));
                                });
                              },
                            ),
                          ),
                          if (hasSelection)
                            Positioned(
                              left: _selectedRect.left,
                              top: _selectedRect.top,
                              width: _selectedRect.width.clamp(1.0, availableWidth),
                              height: _selectedRect.height.clamp(1.0, previewHeightForLayout),
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    _selectedRect = _normalizeRect(_selectedRect.translate(details.delta.dx, details.delta.dy));
                                  });
                                },
                                child: CustomPaint(
                                  painter: _SelectionPainter(),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          if (hasSelection) ...[
                            Positioned(
                              left: _selectedRect.left + (_selectedRect.width / 2) - 9,
                              top: _selectedRect.top - 9,
                              child: GestureDetector(
                                onVerticalDragUpdate: (details) {
                                  setState(() {
                                    final next = _selectedRect.top + details.delta.dy;
                                    _selectedRect = _normalizeRect(Rect.fromLTRB(_selectedRect.left, next, _selectedRect.right, _selectedRect.bottom));
                                  });
                                },
                                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(9))),
                              ),
                            ),
                            Positioned(
                              left: _selectedRect.left + (_selectedRect.width / 2) - 9,
                              top: _selectedRect.bottom - 9,
                              child: GestureDetector(
                                onVerticalDragUpdate: (details) {
                                  setState(() {
                                    final next = _selectedRect.bottom + details.delta.dy;
                                    _selectedRect = _normalizeRect(Rect.fromLTRB(_selectedRect.left, _selectedRect.top, _selectedRect.right, next));
                                  });
                                },
                                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(9))),
                              ),
                            ),
                            Positioned(
                              left: _selectedRect.left - 9,
                              top: _selectedRect.top + (_selectedRect.height / 2) - 9,
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    final next = _selectedRect.left + details.delta.dx;
                                    _selectedRect = _normalizeRect(Rect.fromLTRB(next, _selectedRect.top, _selectedRect.right, _selectedRect.bottom));
                                  });
                                },
                                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(9))),
                              ),
                            ),
                            Positioned(
                              left: _selectedRect.right - 9,
                              top: _selectedRect.top + (_selectedRect.height / 2) - 9,
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    final next = _selectedRect.right + details.delta.dx;
                                    _selectedRect = _normalizeRect(Rect.fromLTRB(_selectedRect.left, _selectedRect.top, next, _selectedRect.bottom));
                                  });
                                },
                                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(9))),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(hasSelection ? '矩形: X ${_selectedRect.left.toStringAsFixed(1)}〜${_selectedRect.right.toStringAsFixed(1)} / Y ${_selectedRect.top.toStringAsFixed(1)}〜${_selectedRect.bottom.toStringAsFixed(1)} / 幅 ${_selectedRect.width.toStringAsFixed(1)}px / 高さ ${_selectedRect.height.toStringAsFixed(1)}px' : '矩形を選択してください', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: hasSelection && !_isOcrProcessing ? _runOcrOnSelection : null,
                icon: _isOcrProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.text_fields),
                label: Text(_isOcrProcessing ? 'OCR実行中...' : 'この矩形でOCR実行'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
