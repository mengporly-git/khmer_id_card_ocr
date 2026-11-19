#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint khmer_id_card_ocr.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'khmer_id_card_ocr'
  s.version          = '0.2.0'
  s.summary          = 'Offline Khmer national ID OCR.'
  s.description      = <<-DESC
Offline Khmer national ID OCR.
                       DESC
  s.homepage         = 'https://github.com/mengporly-git/khmer_id_card_ocr'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'khmer_id_card_ocr/Sources/khmer_id_card_ocr/**/*'
  s.dependency 'Flutter'
  s.dependency 'onnxruntime-objc', '1.20.0'
  s.static_framework = true
  s.vendored_frameworks = 'khmer_id_card_ocr/libtesseract.xcframework'
  s.libraries = 'c++', 'z'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'khmer_id_card_ocr_privacy' => ['khmer_id_card_ocr/Sources/khmer_id_card_ocr/PrivacyInfo.xcprivacy']}
end
