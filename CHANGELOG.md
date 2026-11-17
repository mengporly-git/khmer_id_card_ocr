## 0.1.3

- Show the Flutter app's Gradle settings file paths and where to add JitPack.

## 0.1.2

- Document the public scanner, crop editor, result types, and JSON fields.

## 0.1.1

- Add a crop editor with automatic corner suggestions and perspective correction.
- Read the Khmer name with a dedicated text line model.
- Read the printed English name when the MRZ name is unreadable.
- Read multiline Khmer addresses with Latin number suffixes.
- Recover MRZ2 using additional OCR reads and check-digit validation.
- Read issue and expiry dates from the printed validity row.
- Return null for a Khmer name that the name recognizer cannot read.

## 0.1.0

- Add on-device OCR for Cambodian national ID cards with a three-line front MRZ.
- Add file and byte input, structured JSON output, and a photo picker example.
