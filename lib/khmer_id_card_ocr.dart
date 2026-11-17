import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/id_card_data.dart';
import 'src/id_card_parser.dart';
import 'src/khmer_name_decoder.dart';
import 'src/prepare_image.dart';

export 'src/id_card_data.dart';
export 'src/id_card_crop_page.dart' show showKhmerIdCardCrop;

/// Reads a tightly framed, upright photo of a Cambodian ID card front.
final class KhmerIdCardOcr {
  const KhmerIdCardOcr();

  static const _channel = MethodChannel('khmer_id_card_ocr');
  static const _maxFileSize = 25 * 1024 * 1024;

  /// Reads a local image file. The image is processed on the device.
  Future<KhmerIdCardResult> scanFile(String path) async {
    final file = File(path);
    if (await file.length() > _maxFileSize) {
      throw const FormatException('The image must be 25 MB or smaller.');
    }
    return scanBytes(await file.readAsBytes());
  }

  /// Reads JPEG, PNG or WebP bytes. The card should fill the image.
  Future<KhmerIdCardResult> scanBytes(Uint8List imageBytes) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('Khmer ID OCR supports Android and iOS.');
    }
    if (imageBytes.isEmpty || imageBytes.length > _maxFileSize) {
      throw const FormatException('Choose an image between 1 byte and 25 MB.');
    }

    final images = await compute(prepareIdCardImage, imageBytes);
    final response = await _channel.invokeMapMethod<String, Object>(
      'recognize',
      images,
    );
    if (response == null) {
      throw const FormatException('The OCR engine did not return a result.');
    }
    final dictionary = await rootBundle.loadString(
      'packages/khmer_id_card_ocr/assets/recognition/khmer-name-charset.txt',
    );
    String readTextLine(Object? scores) =>
        scores is Float32List ? decodeKhmerTextLine(scores, dictionary) : '';
    final addressDetail = response['addressDetailLineScores'];

    return parseIdCard(
      mrz: response['mrz'] as String? ?? '',
      mrzWide: response['mrzWide'] as String? ?? '',
      mrzCheck: response['mrzCheck'] as String? ?? '',
      printed: response['printed'] as String? ?? '',
      printedId: response['id'] as String? ?? '',
      printedEnglishName: response['nameEn'] as String? ?? '',
      printedLatinNameLine: readTextLine(response['latinNameLineScores']),
      printedKhmerName: readTextLine(response['nameScores']),
      printedKhmerNameLine: readTextLine(response['nameLineScores']),
      printedAddressLines:
          (response['addressLineScores'] as List<Object?>? ?? const [])
              .map(readTextLine)
              .toList(),
      printedValidityLine: readTextLine(response['validityLineScores']),
      printedAddressDetail: addressDetail is Float32List
          ? decodeKhmerTextLine(
              addressDetail,
              dictionary,
              minimumCConfidence: .85,
            )
          : '',
      now: DateTime.now(),
    );
  }
}
