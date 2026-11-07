#
# smartspectra_flutter supports iOS through Swift Package Manager only,
# because the SmartSpectra Swift SDK is distributed only as a Swift package.
#
# Flutter 3.44+ uses Swift Package Manager by default. On older versions run:
#   flutter config --enable-swift-package-manager
#
Pod::Spec.new do |s|
  s.name             = 'smartspectra_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Unofficial Flutter plugin for the Presage SmartSpectra SDK.'
  s.homepage         = 'https://pub.dev/packages/smartspectra_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'smartspectra_flutter' => 'https://pub.dev/packages/smartspectra_flutter' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '17.0'

  raise <<~MSG
    smartspectra_flutter requires Swift Package Manager on iOS, because the
    SmartSpectra SDK is only distributed as a Swift package.
    Enable it with:  flutter config --enable-swift-package-manager
    then run:        flutter clean && flutter run
  MSG
end
