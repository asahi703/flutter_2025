import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';

class ShiftData {
  final String name;
  final String startTime;
  final String endTime;

  ShiftData({
    required this.name,
    required this.startTime,
    required this.endTime,
  });
}

class WorkInput extends StatefulWidget {
  final List<Map<String, dynamic>> workplaces;
  final void Function(DateTime date, int workplaceId, TimeOfDay startTime, TimeOfDay endTime)
      onSaveShift;

  const WorkInput({
    super.key,
    required this.workplaces,
    required this.onSaveShift,
  });

  @override
  State<WorkInput> createState() => _WorkInputState();
}

class _WorkInputState extends State<WorkInput> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  int? _selectedWorkplaceId;
  bool _isOcrProcessing = false;
final ImagePicker _picker = ImagePicker();

String _ocrRawText = '';
List<String> _ocrLines = [];

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  List<TimeOfDay> _generateTimeOptions() {
    final List<TimeOfDay> times = [];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 15) {
        times.add(TimeOfDay(hour: hour, minute: minute));
      }
    }
    return times;
  }

  Future<void> _startOcrFlow() async {
  try {
    setState(() {
      _isOcrProcessing = true;
    });

    debugPrint('assets画像読み込み開始');

    final ByteData data =
        await rootBundle.load('assets/images/test.png');

    final Uint8List bytes = data.buffer.asUint8List();

    final File tempFile = File(
      '${Directory.systemTemp.path}/ocr_test.png',
    );

    await tempFile.writeAsBytes(bytes);

    debugPrint('assets画像保存完了');

    final XFile imageFile = XFile(tempFile.path);

    final ShiftData? ocrResult =
        await _performOcrFromImage(imageFile);

    if (ocrResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCRで文字を認識できませんでした'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      await _showOcrConfirmationDialog(ocrResult);
    }
  } catch (e) {
    debugPrint(e.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OCRエラー: $e'),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isOcrProcessing = false;
      });
    }
  }
}

  Future<ShiftData?> _performOcrFromImage(XFile imageFile) async {
  try {
    debugPrint('OCR開始');

    final InputImage inputImage =
        InputImage.fromFilePath(imageFile.path);

    debugPrint('InputImage作成完了');

    final textRecognizer = TextRecognizer();

    debugPrint('TextRecognizer作成完了');

    final RecognizedText recognizedText =
        await textRecognizer.processImage(inputImage);

    debugPrint('OCR解析完了');

    await textRecognizer.close();

    final String recognized = recognizedText.text;

    debugPrint('OCR全文');
    debugPrint(recognized);

    setState(() {
      _ocrRawText = recognized;

      _ocrLines = recognized
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    });

    if (recognized.trim().isEmpty) {
      return null;
    }

    return _parseOcrText(recognized);
  } catch (e) {
    debugPrint('OCR内部エラー');
    debugPrint(e.toString());
    rethrow;
  }
}

  Future<Uint8List> _preprocessImage(Uint8List imageBytes) async {
    final image_lib.Image? original = image_lib.decodeImage(imageBytes);
    if (original == null) {
      throw Exception('画像を読み込めませんでした。');
    }

    final image_lib.Image gray = image_lib.grayscale(original);
    final int targetWidth = original.width < 1600 ? 1600 : original.width;
    final image_lib.Image resized = image_lib.copyResize(gray, width: targetWidth);
    // ガウシアンブラー: radiusをnamed引数で渡す
    final image_lib.Image blurred = image_lib.gaussianBlur(resized, radius: 1);
    // コントラスト強化（100がデフォルト、150で強め）
    final image_lib.Image contrasted = image_lib.contrast(blurred, contrast: 150);
    // 輝度ベースで二値化してノイズを減らす
    final image_lib.Image thresholded = image_lib.luminanceThreshold(contrasted, threshold: 0.5);

    return Uint8List.fromList(image_lib.encodeJpg(thresholded, quality: 95));
  }

  ShiftData? _parseOcrText(String text) {
    final String normalized = text
    .replaceAll('：', ':')
    .replaceAll('．', '.')
    .replaceAll('。', '.')
    .replaceAll('時', ':')
    .replaceAll('分', '')
    .replaceAll('―', '-')
    .replaceAll('〜', '-')
    .replaceAll('～', '-')
    .replaceAll('–', '-')
    .replaceAll('ー', '-');

    final List<String> lines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String name = '';
    String startTime = '';
    String endTime = '';
    final RegExp timeRegex =
    RegExp(r'(\d{1,2})[:：.\s]?(\d{2})');

    for (final line in lines) {
      final matches = timeRegex.allMatches(line).toList();
      if (matches.length >= 2) {
        startTime = '${matches[0].group(1)!.padLeft(2, '0')}:${matches[0].group(2)!}';
        endTime = '${matches[1].group(1)!.padLeft(2, '0')}:${matches[1].group(2)!}';
        name = line.replaceAll(timeRegex, '').replaceAll(RegExp(r'[-\s〜～–]+'), ' ').trim();
        break;
      }
    }

    if (startTime.isEmpty || endTime.isEmpty) {
      final matches = timeRegex.allMatches(normalized).toList();
      if (matches.length >= 2) {
        startTime = '${matches[0].group(1)!.padLeft(2, '0')}:${matches[0].group(2)!}';
        endTime = '${matches[1].group(1)!.padLeft(2, '0')}:${matches[1].group(2)!}';
      }
    }

    if (name.isEmpty) {
      final String? nameLine = lines.firstWhere(
        (line) => !timeRegex.hasMatch(line) && line.isNotEmpty,
        orElse: () => '',
      );
      if (nameLine != null && nameLine.isNotEmpty) {
        name = nameLine
            .replaceAll(RegExp(r'氏名|名前|Name|name|出勤|退勤|開始|終了|:|：'), '')
            .trim();
      }
    }

    if (name.isEmpty) {
      name = '認識できませんでした';
    }

    if (startTime.isEmpty || endTime.isEmpty) {
  debugPrint('OCR解析失敗');
  debugPrint(normalized);

  return null;
}

    return ShiftData(name: name, startTime: startTime, endTime: endTime);
  }

  TimeOfDay? _parseTimeOfDay(String timeText) {
    final RegExp matchTime = RegExp(r'(\d{1,2})[:](\d{2})');
    final RegExpMatch? match = matchTime.firstMatch(timeText);
    if (match == null) {
      return null;
    }
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _showOcrConfirmationDialog(ShiftData result) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('OCR結果を確認'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('名前: ${result.name}'),
                  const SizedBox(height: 8),
                  Text('開始時刻: ${result.startTime}'),
                  const SizedBox(height: 8),
                  Text('終了時刻: ${result.endTime}'),
                  const SizedBox(height: 16),
                  const Text('この情報をフォームに反映しますか？'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('反映する'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final TimeOfDay? start = _parseTimeOfDay(result.startTime);
    final TimeOfDay? end = _parseTimeOfDay(result.endTime);
    if (start == null || end == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR結果の時刻を解析できませんでした。')),
        );
      }
      return;
    }

    setState(() {
      _selectedDate = _selectedDate ?? DateTime.now();
      _selectedStartTime = start;
      _selectedEndTime = end;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR結果をフォームに反映しました。勤務先を選択して保存してください。')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _saveShift() {
    if (_selectedDate == null ||
        _selectedWorkplaceId == null ||
        _selectedStartTime == null ||
        _selectedEndTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべての項目を正しく入力してください。')),
      );
      return;
    }
    widget.onSaveShift(
      _selectedDate!,
      _selectedWorkplaceId!,
      _selectedStartTime!,
      _selectedEndTime!,
    );
    setState(() {
      _selectedDate = null;
      _selectedStartTime = null;
      _selectedEndTime = null;
      _selectedWorkplaceId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('シフトを保存しました。')),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'シフト入力',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_isOcrProcessing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _isOcrProcessing ? null : _startOcrFlow,
            icon: const Icon(Icons.image_search),
            label: const Text('画像から読み取る'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _pickDate,
            child: Text(
              _selectedDate == null
                  ? '勤務日を選択'
                  : '勤務日: ${_formatDate(_selectedDate!)}',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedWorkplaceId,
            decoration: const InputDecoration(labelText: '勤務先を選択'),
            items: widget.workplaces.map((place) {
              return DropdownMenuItem<int>(
                value: place['id'] as int,
                child: Text('${place['name']} (¥${place['hourlyWage']})'),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedWorkplaceId = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TimeOfDay>(
                  value: _selectedStartTime,
                  decoration: const InputDecoration(labelText: '開始時刻'),
                  items: _generateTimeOptions().map((time) {
                    return DropdownMenuItem<TimeOfDay>(
                      value: time,
                      child: Text(_formatTime(time)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedStartTime = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<TimeOfDay>(
                  value: _selectedEndTime,
                  decoration: const InputDecoration(labelText: '終了時刻'),
                  items: _generateTimeOptions().map((time) {
                    return DropdownMenuItem<TimeOfDay>(
                      value: time,
                      child: Text(_formatTime(time)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedEndTime = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveShift,
            child: const Text('シフトを保存'),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 20),

ExpansionTile(
  title: const Text('OCRデバッグ情報'),
  children: [
    Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OCR全文',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade200,
            child: SelectableText(_ocrRawText),
          ),

          const SizedBox(height: 20),

          const Text(
            'OCR行解析',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          ..._ocrLines.map(
            (line) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade100,
              child: Text(line),
            ),
          ),
        ],
      ),
    ),
  ],
),
        ],
      ),
    );
  }
}
