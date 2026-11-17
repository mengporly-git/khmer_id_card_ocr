import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Map<String, Object> prepareIdCardImage(Uint8List bytes) {
  final image = decodeIdCardPhoto(bytes);
  if (image.width <= image.height || image.width < 360) {
    throw const FormatException('Use an upright, landscape photo of the card.');
  }
  final resized = img.copyResize(
    image,
    width: 1650,
    interpolation: img.Interpolation.cubic,
  );
  final nameRegion = _crop(resized, .425, .10, .965, .171);
  final name = _prepareKhmerName(_trimTextMargin(nameRegion));
  final fullNameLine = _findKhmerNameLine(resized);
  final gray = img.grayscale(resized);
  final nameBottom = fullNameLine?.bottom;
  final latinRegion = _findLatinNameLine(gray, nameBottom);
  final latin = _trimTextMargin(
    latinRegion ?? _crop(gray, .412, .171, .965, .218),
    stopAtGap: true,
  );
  final body = _findBodyFields(resized, nameBottom);
  final leveled = _levelMrz(gray);
  final mrzTop = identical(leveled, gray) ? .64 : .54;
  final mrzCheck = _findMrzCheck(leveled);

  return {
    'mrz': _paddedPng(_crop(leveled, .035, mrzTop, .98, .95)),
    if (mrzTop > .54)
      'mrzWide': _paddedPng(_crop(leveled, .035, .54, .98, .95)),
    'mrzCheck': ?mrzCheck,
    'printed': _paddedPng(_crop(gray, .245, .04, .985, .625)),
    'id': _paddedPng(_crop(gray, .64, .02, .96, .127)),
    'nameEn': _paddedPng(latin),
    if (latinRegion != null) 'latinNameLine': _encodeTextLine(latin),
    'nameInput': name.pixels,
    'nameWidth': name.width,
    'nameHeight': name.height,
    'nameLine': ?fullNameLine?.tensor,
    if (body.address.isNotEmpty) 'addressLines': body.address,
    'addressDetailLine': ?body.addressDetail,
    'validityLine': ?body.validity,
  };
}

({Map<String, Object> tensor, double bottom})? _findKhmerNameLine(
  img.Image image,
) {
  if (image.height < 100) return null;

  // Measure the bold Muol label to locate the name row. The portrait is left
  // of this strip, and the Latin name and card number begin farther right.
  const firstBand = 5;
  final ink = List<double>.filled(22, 0);
  final left = (image.width * .25).round();
  final right = (image.width * .39).round();
  for (var band = firstBand; band < ink.length; band++) {
    final top = (image.height * band / 100).round();
    final bottom = (image.height * (band + 1) / 100).round();
    var dark = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (image.getPixel(x, y).luminanceNormalized < .54) dark++;
      }
    }
    ink[band] = dark / ((right - left) * (bottom - top));
  }

  for (var start = firstBand; start + 1 < ink.length; start++) {
    if (ink[start] < .16 || ink[start + 1] < .16) continue;
    var end = start + 2;
    while (end < ink.length && ink[end] >= .12) {
      end++;
    }
    if (end == ink.length || end - start > 7) return null;

    // The detached vowel marks extend above the bold text. Leave room for
    // them and for the name to rise toward the right on a tilted photo.
    final region = _crop(
      image,
      .245,
      math.max(.025, start / 100 - .038),
      .965,
      end / 100 + .007,
    );
    return (tensor: _lineTensor(region), bottom: end / 100);
  }
  return null;
}

img.Image? _findLatinNameLine(img.Image image, double? nameBottom) {
  if (nameBottom == null) return null;
  final rows = _inkRows(image, .375, .64, nameBottom + .008, nameBottom + .085);
  if (rows.isEmpty) return null;
  final row = rows.first;
  // The birth row can touch the Latin letters on a tilted card.
  final bottom = math.min(row.bottom + .006, row.top + .033);
  return _crop(image, .35, row.top - .010, .965, bottom);
}

({
  List<Map<String, Object>> address,
  Map<String, Object>? addressDetail,
  Map<String, Object>? validity,
})
_findBodyFields(img.Image image, double? nameBottom) {
  const empty = (
    address: <Map<String, Object>>[],
    addressDetail: null,
    validity: null,
  );
  if (nameBottom == null) return empty;
  // In the label column, date of birth and birthplace precede the address.
  final rows = _inkRows(image, .255, .39, nameBottom + .032, .61);
  if (rows.length < 3) return empty;
  final address = rows[2];
  return (
    address: [
      _lineTensor(
        _crop(image, .205, address.top - .012, .94, address.bottom + .006),
      ),
      if (rows.length > 3)
        _lineTensor(
          _crop(image, .205, rows[3].top - .019, .94, rows[3].bottom + .006),
        ),
    ],
    // Trim the label and leave room above the text for thin Latin suffixes.
    addressDetail: _lineTensor(
      _crop(image, .30, address.top - .027, .94, address.bottom + .010),
    ),
    validity: rows.length > 4
        ? _lineTensor(
            _crop(image, .205, rows[4].top - .019, .94, rows[4].bottom + .010),
          )
        : null,
  );
}

Uint8List? _findMrzCheck(img.Image image) {
  final rows = _inkRows(image, .12, .93, .57, .94);
  for (var i = 1; i + 1 < rows.length; i++) {
    final before = rows[i - 1];
    final middle = rows[i];
    final after = rows[i + 1];
    final firstSpacing = middle.top - before.top;
    final secondSpacing = after.top - middle.top;
    // The three MRZ rows have similar height and even spacing. Reject stray
    // lines from nearby printed fields or the lower edge of the photograph.
    if ([
          before.bottom - before.top,
          middle.bottom - middle.top,
          after.bottom - after.top,
        ].every((height) => height >= .022 && height <= .079) &&
        firstSpacing >= .048 &&
        secondSpacing >= .048 &&
        (firstSpacing - secondSpacing).abs() <= .022) {
      return _paddedPng(
        _crop(image, .90, middle.top - .014, .98, middle.bottom + .014),
      );
    }
  }
  return null;
}

List<({double top, double bottom})> _inkRows(
  img.Image image,
  double left,
  double right,
  double top,
  double bottom,
) {
  const bands = 200;
  final startX = (left * image.width).round();
  final endX = (right * image.width).round();
  final rows = <({double top, double bottom})>[];
  var start = 0;
  var last = -3;
  void finishRow() {
    if (last - start >= 2) {
      rows.add((top: start / bands, bottom: (last + 1) / bands));
    }
  }

  for (
    var band = (top * bands).round();
    band < (bottom * bands).round();
    band++
  ) {
    final startY = (band * image.height / bands).round();
    final endY = ((band + 1) * image.height / bands).round();
    if (startY == endY) continue;
    var dark = 0;
    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        if (image.getPixel(x, y).luminanceNormalized < .54) dark++;
      }
    }
    if (dark < .16 * (endX - startX) * (endY - startY)) continue;
    if (band - last > 2) {
      finishRow();
      start = band;
    }
    last = band;
  }
  finishRow();
  return rows;
}

Map<String, Object> _lineTensor(img.Image region) =>
    _encodeTextLine(_trimTextMargin(region, stopAtGap: true));

Map<String, Object> _encodeTextLine(img.Image region) {
  final line = _prepareKhmerName(region);
  return {'input': line.pixels, 'width': line.width, 'height': line.height};
}

img.Image decodeIdCardPhoto(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder is! img.JpegDecoder &&
      decoder is! img.PngDecoder &&
      decoder is! img.WebPDecoder) {
    throw const FormatException('Choose a JPEG, PNG or WebP image.');
  }
  final dimensions = decoder?.startDecode(bytes);
  if (dimensions == null || dimensions.width * dimensions.height > 30e6) {
    throw const FormatException('Choose a readable image under 30 megapixels.');
  }
  final decoded = decoder?.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('The image is unreadable.');
  }
  return img.bakeOrientation(decoded);
}

img.Image _levelMrz(img.Image image) {
  final width = image.width;
  final height = image.height;
  final centerX = width ~/ 2;
  final ink = <(int, int)>[];
  // Sample the lower interior so card edges and the portrait do not set the angle.
  for (var y = (height * .56).round(); y < height * .885; y += 3) {
    for (var x = (width * .11).round(); x < width * .93; x += 3) {
      if (image.getPixel(x, y).rNormalized < .51) {
        ink.add((x - centerX, y));
      }
    }
  }
  if (ink.isEmpty) return image;

  // Dark strokes cluster into the same rows when projected at the text angle.
  const maxAngle = 8;
  final padding = (centerX * math.tan(maxAngle * math.pi / 180)).ceil();
  final rows = List<int>.filled((height + 2 * padding) ~/ 4 + 2, 0);
  int score(double angle) {
    rows.fillRange(0, rows.length, 0);
    final slope = math.tan(angle * math.pi / 180);
    for (final (x, y) in ink) {
      rows[((y + x * slope + padding) / 4).floor()]++;
    }
    return rows.fold(0, (sum, count) => sum + count * count);
  }

  final uprightScore = score(0);
  var bestScore = uprightScore;
  var bestAngle = 0.0;
  for (var angle = -maxAngle.toDouble(); angle <= maxAngle; angle += .5) {
    final candidate = score(angle);
    if (candidate > bestScore) {
      bestScore = candidate;
      bestAngle = angle;
    }
  }
  if (bestAngle.abs() < 1 || bestScore < uprightScore * 1.15) return image;

  image.backgroundColor = img.ColorRgb8(255, 255, 255);
  final rotated = img.copyRotate(
    image,
    angle: bestAngle,
    interpolation: img.Interpolation.linear,
  );
  return img.copyCrop(
    rotated,
    x: (rotated.width - width) ~/ 2,
    y: (rotated.height - height) ~/ 2,
    width: width,
    height: height,
  );
}

img.Image _crop(
  img.Image image,
  double left,
  double top,
  double right,
  double bottom,
) {
  final x = (left * image.width).round();
  final y = (top * image.height).round();
  return img.copyCrop(
    image,
    x: x,
    y: y,
    width: math.max(1, (right * image.width).round() - x),
    height: math.max(1, (bottom * image.height).round() - y),
  );
}

Uint8List _paddedPng(img.Image region) {
  final padded = img.Image(
    width: region.width + 36,
    height: region.height + 36,
  );
  img.fill(padded, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(padded, region, dstX: 18, dstY: 18);
  return img.encodePng(padded, level: 3);
}

({Float32List pixels, int width, int height}) _prepareKhmerName(
  img.Image line,
) {
  // The recognizer was trained on these aspect-ratio buckets.
  final ratio = (line.width / line.height).round().clamp(1, 20);
  final height = ratio == 1 ? 64 : 48;
  final width = ratio * height;
  final resized = img.copyResize(
    line,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );
  final area = width * height;
  final input = Float32List(area * 3);
  var index = 0;
  for (final pixel in resized) {
    input[index] = 2 * pixel.rNormalized - 1;
    input[area + index] = 2 * pixel.gNormalized - 1;
    input[2 * area + index] = 2 * pixel.bNormalized - 1;
    index++;
  }
  return (pixels: input, width: width, height: height);
}

/// Finds columns with connected-looking strokes and removes blank side margins.
/// The pixels sent to the model retain their original colors and tonal range.
img.Image _trimTextMargin(img.Image region, {bool stopAtGap = false}) {
  final levels = Uint8List(region.width * region.height);
  final histogram = List<int>.filled(256, 0);
  var index = 0;
  var total = 0;
  for (final pixel in region) {
    final level = (pixel.luminanceNormalized * 255).round().clamp(0, 255);
    levels[index++] = level;
    histogram[level]++;
    total += level;
  }

  // Otsu threshold for the projection only, so exposure changes do not move
  // the crop toward the background pattern.
  var ink = 0;
  var inkSum = 0;
  var threshold = 0;
  var best = 0.0;
  for (var level = 0; level < histogram.length; level++) {
    ink += histogram[level];
    inkSum += level * histogram[level];
    final background = levels.length - ink;
    if (ink == 0 || background == 0) continue;
    final separation = inkSum / ink - (total - inkSum) / background;
    final score = ink * background * separation * separation;
    if (score > best) {
      best = score;
      threshold = level;
    }
  }
  if (best == 0) return region;

  final minInk = math.max(2, (region.height * .20).round());
  final minRun = math.max(2, (region.height * .07).round());
  final maxGap = (region.height * .9).round();
  var first = region.width;
  var last = 0;
  var run = 0;
  for (var x = 0; x < region.width; x++) {
    var darkPixels = 0;
    for (var y = 0; y < region.height; y++) {
      if (levels[y * region.width + x] <= threshold) darkPixels++;
    }
    run = darkPixels >= minInk ? run + 1 : 0;
    if (run >= minRun) {
      // In the English row, a large gap separates the name from the line below.
      final start = x - run + 1;
      if (stopAtGap && last > 0 && start - last > maxGap) break;
      first = math.min(first, start);
      last = x + 1;
    }
  }

  if (last <= first) return region;
  final margin = math.max(2, (region.height * .12).round());
  final left = math.max(0, first - margin);
  final right = math.min(region.width, last + margin);
  return img.copyCrop(
    region,
    x: left,
    y: 0,
    width: right - left,
    height: region.height,
  );
}
