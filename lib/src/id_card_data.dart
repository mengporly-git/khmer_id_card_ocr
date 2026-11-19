/// The fields read from the front of a Cambodian national ID card.
///
/// Fields that could not be read are `null`. Dates use `YYYY-MM-DD`.
final class KhmerIdCardData {
  /// Creates a set of card fields with unspecified values set to `null`.
  const KhmerIdCardData({
    this.idNumber,
    this.lastNameKh,
    this.firstNameKh,
    this.dob,
    this.placeOfBirth,
    this.gender,
    this.lastNameEn,
    this.firstNameEn,
    this.expiredDate,
    this.issuedDate,
    this.address,
    this.mrz1,
    this.mrz2,
    this.mrz3,
  });

  /// The nine-digit document number, including any leading zeroes.
  final String? idNumber;

  /// The surname printed in Khmer script.
  final String? lastNameKh;

  /// The given name or names printed in Khmer script.
  final String? firstNameKh;

  /// The cardholder's date of birth in `YYYY-MM-DD` format.
  final String? dob;

  /// The birthplace printed next to ទីកន្លែងកំណើត.
  final String? placeOfBirth;

  /// The card's sex marker, either `M` or `F` when recognized.
  final String? gender;

  /// The surname read from the printed Latin name or machine-readable zone.
  final String? lastNameEn;

  /// The given name or names read from the printed Latin name or MRZ.
  final String? firstNameEn;

  /// The card's expiry date in `YYYY-MM-DD` format.
  final String? expiredDate;

  /// The issue date read from the printed validity row, in `YYYY-MM-DD` format.
  final String? issuedDate;

  /// The printed address, with its lines joined by spaces.
  ///
  /// The text may include Khmer and Latin characters in the same field.
  final String? address;

  /// The normalized first MRZ line, which contains the document number.
  final String? mrz1;

  /// The normalized second MRZ line, including the dates and composite digit.
  ///
  /// This field is available when its check digits can be validated.
  final String? mrz2;

  /// The normalized third MRZ line, which contains the surname and given names.
  final String? mrz3;

  /// Returns all field keys, including keys with `null` values.
  Map<String, String?> toJson() => {
    'idNumber': idNumber,
    'lastNameKh': lastNameKh,
    'firstNameKh': firstNameKh,
    'dob': dob,
    'placeOfBirth': placeOfBirth,
    'gender': gender,
    'lastNameEn': lastNameEn,
    'firstNameEn': firstNameEn,
    'expiredDate': expiredDate,
    'issuedDate': issuedDate,
    'address': address,
    'MRZ1': mrz1,
    'MRZ2': mrz2,
    'MRZ3': mrz3,
  };
}

/// The result of a card scan, with the recognized fields under [data].
final class KhmerIdCardResult {
  /// Wraps the recognized card fields.
  const KhmerIdCardResult(this.data);

  /// The fields recognized on the card.
  final KhmerIdCardData data;

  /// Returns a JSON-ready map with the card fields under the `data` key.
  Map<String, Object?> toJson() => {'data': data.toJson()};
}
