import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:khmer_id_card_ocr/src/prepare_image.dart';

void main() {
  test('follows the Latin name and address rows below the Khmer name', () {
    final image = img.Image(width: 1650, height: 1000);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);
    for (final y in [145, 235, 295, 365, 425, 500]) {
      img.fillRect(image, x1: 420, y1: y, x2: 600, y2: y + 25, color: black);
    }
    img.fillRect(image, x1: 610, y1: 196, x2: 845, y2: 219, color: black);

    final prepared = prepareIdCardImage(img.encodePng(image));
    final latin = img.decodePng(prepared['nameEn']! as Uint8List)!;
    expect(latin.where((pixel) => pixel.r < 128).length, greaterThan(5000));
    expect(prepared['addressLines'], hasLength(2));
  });

  test('finds the full Khmer name row above the smaller printed text', () {
    final image = img.Image(width: 1650, height: 1000);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);
    img.fillRect(image, x1: 420, y1: 150, x2: 606, y2: 179, color: black);
    img.fillRect(image, x1: 618, y1: 150, x2: 697, y2: 178, color: black);
    img.fillRect(image, x1: 706, y1: 150, x2: 856, y2: 178, color: black);
    img.fillRect(
      image,
      x1: 625,
      y1: 130,
      x2: 646,
      y2: 138,
      color: img.ColorRgb8(170, 0, 0),
    );
    img.fillRect(
      image,
      x1: 420,
      y1: 217,
      x2: 850,
      y2: 237,
      color: img.ColorRgb8(0, 0, 170),
    );

    final prepared = prepareIdCardImage(img.encodePng(image));
    expect(prepared['nameLine'], isA<Map<String, Object>>());
    final line = prepared['nameLine']! as Map<String, Object>;
    final pixels = line['input']! as Float32List;
    final area = (line['width']! as int) * (line['height']! as int);
    final locations = List.generate(area, (index) => index);

    expect(locations.any((i) => pixels[i] - pixels[2 * area + i] > .7), isTrue);
    expect(
      locations.any((i) => pixels[2 * area + i] - pixels[i] > .7),
      isFalse,
    );
  });

  test('keeps the full first MRZ row in a tilted photo', () {
    final white = img.ColorRgb8(255, 255, 255);
    final image = img.Image(width: 1280, height: 806, backgroundColor: white);
    img.fill(image, color: white);
    const rows = [
      'IDKHM1234567897<<<<<<<<<<<<<<<',
      '8009124M3009129KHM<<<<<<<<<<<8',
      'HENG<<SAMOL<<<<<<<<<<<<<<<<<<<',
    ];
    for (var i = 0; i < rows.length; i++) {
      img.drawString(
        image,
        rows[i],
        font: img.arial48,
        x: 125,
        y: 460 + 65 * i,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
    final tilted = img.copyRotate(
      image,
      angle: -4,
      interpolation: img.Interpolation.linear,
    );
    final photo = img.copyCrop(
      tilted,
      x: (tilted.width - image.width) ~/ 2,
      y: (tilted.height - image.height) ~/ 2,
      width: image.width,
      height: image.height,
    );

    final images = prepareIdCardImage(img.encodeJpg(photo));
    final mrz = img.decodePng(images['mrz']! as Uint8List)!;

    int firstInkRow(int left, int right) =>
        mrz.where((p) => p.x >= left && p.x < right && p.r < 128).first.y;

    final left = firstInkRow(100, 280);
    final right = firstInkRow(560, 690);
    expect(left, inInclusiveRange(30, 105));
    expect(right, inInclusiveRange(30, 105));
    expect((left - right).abs(), lessThan(12));
  });
}
