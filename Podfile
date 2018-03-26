platform :ios, '9.0'
source 'https://github.com/CocoaPods/Specs.git'

# By default, ignore all warnings from installed Pods.
inhibit_all_warnings!

use_frameworks!

def shared_pods
  # OWS Pods
  # pod 'SQLCipher', path: '../sqlcipher2', :inhibit_warnings => false
  pod 'SQLCipher', :git => 'https://github.com/sqlcipher/sqlcipher.git', :commit => 'd5c2bec'
  # pod 'YapDatabase/SQLCipher', path: '../YapDatabase', :inhibit_warnings => false
  pod 'YapDatabase/SQLCipher', :git => 'https://github.com/signalapp/YapDatabase.git', branch: 'release/unencryptedHeaders'
  # pod 'AxolotlKit',   path: '../SignalProtocolKit', :inhibit_warnings => false
  pod 'SignalServiceKit', path: '.', :inhibit_warnings => false
  pod 'AxolotlKit', git: 'https://github.com/signalapp/SignalProtocolKit.git'
  #pod 'AxolotlKit', path: '../SignalProtocolKit', :inhibit_warnings => false
  pod 'HKDFKit', git: 'https://github.com/signalapp/HKDFKit.git', branch: 'mkirk/framework-friendly'
  #pod 'HKDFKit', path: '../HKDFKit', :inhibit_warnings => false
  pod 'Curve25519Kit', git: 'https://github.com/signalapp/Curve25519Kit', branch: 'mkirk/framework-friendly'
  #pod 'Curve25519Kit', path: '../Curve25519Kit', :inhibit_warnings => false
  pod 'GRKOpenSSLFramework', git: 'https://github.com/signalapp/GRKOpenSSLFramework'
  #pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework', :inhibit_warnings => false

  # third party pods
  pod 'AFNetworking'
  pod 'JSQMessagesViewController',  git: 'https://github.com/signalapp/JSQMessagesViewController.git', branch: 'mkirk/share-compatible'
  #pod 'JSQMessagesViewController',   path: '../JSQMessagesViewController', :inhibit_warnings => false
  pod 'Mantle'
  pod 'PureLayout'
  pod 'Reachability'
  pod 'SocketRocket', :git => 'https://github.com/facebook/SocketRocket.git'
  pod 'YYImage'
end

target 'Signal' do
  shared_pods
  pod 'ATAppUpdater'
  pod 'SSZipArchive'

  target 'SignalTests' do
    inherit! :search_paths
  end
end

target 'SignalShareExtension' do
  shared_pods
end

target 'SignalMessaging' do
  shared_pods
end

post_install do |installer|
  # Disable some asserts when building for tests
  set_building_for_tests_config(installer, 'SignalServiceKit')
  enable_extension_support_for_purelayout(installer)
end

# There are some asserts and debug checks that make testing difficult - e.g. Singleton asserts
def set_building_for_tests_config(installer, target_name)
  target = installer.pods_project.targets.detect { |target| target.to_s == target_name }
  if target == nil
    throw "failed to find target: #{target_name}"
  end

  build_config_name = "Test"
  build_config = target.build_configurations.detect { |config| config.to_s == build_config_name }
  if build_config == nil
    throw "failed to find config: #{build_config_name} for target: #{target_name}"
  end

  puts "--[!] Disabling singleton enforcement for target: #{target} in config: #{build_config}"
  existing_definitions = build_config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']

  if existing_definitions == nil || existing.length == 0
    existing_definitions = "$(inheritied)"
  end
  build_config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = "#{existing_definitions} POD_CONFIGURATION_TEST=1 COCOAPODS=1 SSK_BUILDING_FOR_TESTS=1"
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
        if build_configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
          build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['$(inherited)', 'PURELAYOUT_APP_EXTENSIONS=1']
        end
      end
    end
  end
end

