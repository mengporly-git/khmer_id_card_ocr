# Khmer ID Card OCR

Flutter plugin for reading the front of a Cambodian national ID card with an
`IDKHM` machine-readable zone (MRZ). Android and iOS process the photo on the
device. The Khmer name uses a dedicated text line recognizer, and the English
name uses its own pass over the printed line with the MRZ as a fallback. A
network connection is needed to resolve build dependencies. Scanning works offline.

## Install

Add the package to your Flutter app.

```sh
flutter pub add khmer_id_card_ocr
```

The plugin requires Flutter 3.47+, Dart 3.13+, Android API 24+ and iOS 15+.
Android resolves Tesseract4Android from JitPack.

If your build enforces settings-only repositories, open
`<your-flutter-app>/android/settings.gradle.kts` (Kotlin) or
`<your-flutter-app>/android/settings.gradle` (Groovy). Add the `maven` entry
inside `dependencyResolutionManagement { repositories { … } }` alongside
your existing repositories.

```kotlin
maven {
    url = uri("https://jitpack.io")
    content { includeGroup("cz.adaptech.tesseract4android") }
}
```

For Groovy, use `url = 'https://jitpack.io'` in the same `maven` block.

## Scan a photo

```dart
import 'dart:convert';

import 'package:khmer_id_card_ocr/khmer_id_card_ocr.dart';

Future<String> readCard(String imagePath) async {
  final result = await const KhmerIdCardOcr().scanFile(imagePath);
  return jsonEncode(result.toJson());
}
```

Use `scanBytes(Uint8List)` if your image picker or upload flow already has
bytes.

### Crop before scanning

Call `showKhmerIdCardCrop` from a widget under `MaterialApp` and pass the
photo bytes from your image picker. The editor suggests the card's edges,
lets the user adjust the corners, and returns a straightened JPEG when
they confirm. If they go back, it returns `null`.

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:khmer_id_card_ocr/khmer_id_card_ocr.dart';

Future<String?> cropAndReadCard(BuildContext context, Uint8List bytes) async {
  final cropped = await showKhmerIdCardCrop(context, bytes);
  if (cropped == null) return null;

  final result = await const KhmerIdCardOcr().scanBytes(cropped);
  return jsonEncode(result.toJson());
}
```

The example app opens the gallery, shows the crop editor, and displays
copyable JSON. Run `flutter pub get` and `flutter run` from `example/`.
Add `NSPhotoLibraryUsageDescription` to your host app if it uses the example's
iOS photo-picker flow.

### Example result

```json
{
  "data": {
    "idNumber": "123456789",
    "lastNameKh": "ហេង",
    "firstNameKh": "សំអុល",
    "dob": "1980-09-12",
    "gender": "M",
    "lastNameEn": "HENG",
    "firstNameEn": "SAMOL",
    "expiredDate": "2030-09-12",
    "issuedDate": "2020-09-13",
    "placeOfBirth": "ឃុំព្រៃកប្បាស ស្រុកព្រៃកប្បាស តាកែវ",
    "address": "ភូមិព្រៃធំ ឃុំពេជសារ ស្រុកកោះអណ្តែត តាកែវ",
    "MRZ1": "IDKHM1234567897<<<<<<<<<<<<<<<",
    "MRZ2": "8009124M3009129KHM<<<<<<<<<<<8",
    "MRZ3": "HENG<<SAMOL<<<<<<<<<<<<<<<<<<<"
  }
}
```

- Use a tightly cropped, upright landscape image that includes the entire
  card. JPEG, PNG and WebP are supported up to 25 MB and 30 megapixels.
- Each key is always present. Unreadable fields are `null`. Dates use
  `YYYY-MM-DD`. The issue date comes from printed text. The MRZ date has a
  two-digit year, and the parser uses the printed year when available.
- The Khmer line recognizer reads the bold Khmer OS Muol name row and the
  smaller Battambang birthplace and address rows. `placeOfBirth` is the
  text printed next to ទីកន្លែងកំណើត. The printed Latin name is read from the
  row below the Khmer name and compared with the MRZ. Dates and other body
  text go through a separate Tesseract pass.
- The returned names and address are OCR transcriptions. Review them before
  saving or submitting. MRZ checks detect some transcription errors.
- Unsupported, corrupt or unidentifiable images throw `FormatException`.
  A native OCR failure throws `PlatformException`.

## Components

- [anaksor-ocr Khmer recognition model](https://huggingface.co/Sokheng/anaksor-ocr/tree/5518ec408419be074e8214712c673d41ffa84285),
  bundled as a 27 MiB model with INT8 weights for constant matrix multiplications.
- [ONNX Runtime](https://onnxruntime.ai/) runs the Khmer name recognizer locally.

- [Tesseract traineddata](https://tesseract-ocr.github.io/tessdoc/Data-Files)
  via the integerized Khmer and English Tesseract.js language packages.
- [Tesseract4Android 4.9.0](https://github.com/adaptech-cz/Tesseract4Android/tree/4.9.0).
- [SwiftyTesseract libtesseract 0.2.0](https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0)
  with the iOS device and simulator slices.
- [ICAO Doc 9303, Part 5](https://www.icao.int/sites/default/files/publications/DocSeries/9303_p5_cons_en.pdf)
  for the TD1 MRZ field positions and check digits.
