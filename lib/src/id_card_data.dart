/// The fields read from the front of a Cambodian national ID card.
///
/// A null value means the field could not be read. Dates use DD/MM/YYYY.
final class KhmerIdCardData {
  const KhmerIdCardData({
    this.idNumber,
    this.lastNameKh,
    this.firstNameKh,
    this.dob,
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

  final String? idNumber;
  final String? lastNameKh;
  final String? firstNameKh;
  final String? dob;
  final String? gender;
  final String? lastNameEn;
  final String? firstNameEn;
  final String? expiredDate;
  final String? issuedDate;
  final String? address;
  final String? mrz1;
  final String? mrz2;
  final String? mrz3;

  Map<String, String?> toJson() => {
    'idNumber': idNumber,
    'lastNameKh': lastNameKh,
    'firstNameKh': firstNameKh,
    'dob': dob,
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

final class KhmerIdCardResult {
  const KhmerIdCardResult(this.data);

  final KhmerIdCardData data;

  Map<String, Object?> toJson() => {'data': data.toJson()};
}
