import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:khmer_id_card_ocr/khmer_id_card_ocr.dart';

void main() => runApp(const MaterialApp(home: CardScanner()));

class CardScanner extends StatefulWidget {
  const CardScanner({super.key});

  @override
  State<CardScanner> createState() => _CardScannerState();
}

class _CardScannerState extends State<CardScanner> {
  final _picker = ImagePicker();
  final _ocr = const KhmerIdCardOcr();

  bool _busy = false;
  String? _json;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      if (await file.length() > 25 * 1024 * 1024) {
        throw const FormatException('The image must be 25 MB or smaller.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final cropped = await showKhmerIdCardCrop(context, bytes);
      if (!mounted || cropped == null) return;
      setState(() => _json = null);
      final result = await _ocr.scanBytes(cropped);
      if (!mounted) return;
      setState(() {
        _json = const JsonEncoder.withIndent('  ').convert(result.toJson());
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Could not scan the image.');
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Could not open or scan the image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final json = _json;
    return Scaffold(
      appBar: AppBar(title: const Text('Khmer ID Card OCR')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Scan an ID card',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose a photo of the card front with all three lines at the bottom visible.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_busy ? 'Reading card…' : 'Choose image'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (json != null) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: json)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy JSON'),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  json,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
