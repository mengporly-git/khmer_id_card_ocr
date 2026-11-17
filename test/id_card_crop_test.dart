import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:khmer_id_card_ocr/src/id_card_crop.dart';

void main() {
  const corners = <Point<double>>[
    Point(.19, .26),
    Point(.80, .30),
    Point(.73, .78),
    Point(.25, .72),
  ];

  img.Image makePhoto() {
    final photo = img.Image(width: 500, height: 400);
    img.fill(photo, color: img.ColorRgb8(58, 58, 58));
    img.fillPolygon(
      photo,
      vertices: corners
          .map(
            (p) => img.Point(p.x * (photo.width - 1), p.y * (photo.height - 1)),
          )
          .toList(),
      color: img.ColorRgb8(225, 225, 225),
    );
    return photo;
  }

  test('suggests the four edges of an off-center perspective photo', () {
    final photo = loadCardCropPhoto(img.encodePng(makePhoto()));
    for (var i = 0; i < corners.length; i++) {
      expect(photo.corners[i].distanceTo(corners[i]), lessThan(.035));
    }
  });

  test(
    'suggests the corners of a rotated card beside a larger bright object',
    () {
      final photo = img.Image(width: 850, height: 490);
      img.fill(photo, color: img.ColorRgb8(36, 36, 36));
      final white = img.ColorRgb8(226, 226, 226);
      img.fillRect(photo, x1: 35, y1: 100, x2: 295, y2: 360, color: white);
      const rotated = [
        Point(438.0, 118.0),
        Point(740.0, 250.0),
        Point(664.0, 423.0),
        Point(362.0, 291.0),
      ];
      img.fillPolygon(
        photo,
        vertices: rotated.map((p) => img.Point(p.x, p.y)).toList(),
        color: white,
      );

      final selection = loadCardCropPhoto(img.encodePng(photo)).corners;
      for (var i = 0; i < rotated.length; i++) {
        final point = selection[i];
        expect(
          Point(point.x * 849, point.y * 489).distanceTo(rotated[i]),
          lessThan(18),
        );
      }
    },
  );

  test('maps a quadrilateral to a straight landscape card', () {
    final photo = makePhoto();
    // A stripe three quarters across the selected top edge belongs there in
    // the output even though the bottom edge is narrower.
    img.fillCircle(
      photo,
      x: 323,
      y: 119,
      radius: 9,
      color: img.ColorRgb8(230, 30, 30),
    );
    final bytes = straightenCardCrop((
      bytes: img.encodePng(photo),
      corners: corners,
    ));
    final card = img.decodeJpg(bytes)!;
    expect(card.width / card.height, closeTo(1.586, .005));
    expect(card.getPixel(30, card.height ~/ 2).r, greaterThan(190));
    final reds = card.where((p) => p.r > 130 && p.g < 100).map((p) => p.x);
    expect(reds, isNotEmpty);
    expect(
      reds.reduce((a, b) => a + b) / reds.length / card.width,
      inInclusiveRange(.68, .83),
    );
  });

  test('preserves grayscale in the editor and straightened preview', () {
    final photo = img.Image(width: 500, height: 400, numChannels: 1);
    img.fillRect(
      photo,
      x1: 0,
      y1: 0,
      x2: 499,
      y2: 399,
      color: img.ColorRgb8(220, 220, 220),
    );
    final bytes = img.encodePng(photo);
    for (final output in [
      loadCardCropPhoto(bytes).preview,
      straightenCardCrop((bytes: bytes, corners: corners)),
    ]) {
      final pixel = img.decodeJpg(output)!.getPixel(100, 100);
      expect([pixel.r, pixel.g, pixel.b], everyElement(closeTo(220, 2)));
    }
  });
}
