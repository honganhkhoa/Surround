#!/usr/bin/env ruby
require 'json'
require 'fileutils'
require 'pathname'
require 'xcodeproj'

base = Pathname.new(__dir__)
build = base + '.build'
FileUtils.mkdir_p(build + 'Previews')
FileUtils.mkdir_p(build + 'Info')
variants = JSON.parse((base + 'variants.json').read)
project = Xcodeproj::Project.new((build + 'Comparison.xcodeproj').to_s)
source = project.main_group.new_file((base + 'IconComparisonApp.swift').relative_path_from(build).to_s)
composer = '/Applications/Icon Composer.app/Contents/Executables/ictool'
variants.each do |v|
  target = project.new_target(:application, v.fetch('target'), :ios, '26.0')
  target.source_build_phase.add_file_reference(source)
  preview = build + 'Previews' + "#{v.fetch('id')}.png"
  if v['icon']
    icon = (base + v.fetch('icon')).cleanpath
    ref = project.main_group.new_file(icon.relative_path_from(build).to_s)
    ref.last_known_file_type = 'folder.icon'
    target.resources_build_phase.add_file_reference(ref)
    icon_name = icon.basename('.icon').to_s
    ok = system(composer, icon.to_s, '--export-image', '--output-file', preview.to_s,
      '--platform', 'iOS', '--rendition', 'Default', '--width', '512', '--height', '512',
      '--scale', '1', '--design-generation', '27')
    abort "Preview failed: #{v.fetch('id')}" unless ok
  else
    catalog = build + 'Reference.xcassets'
    FileUtils.mkdir_p(catalog)
    (catalog + 'Contents.json').write(JSON.generate({info: {author: 'xcode', version: 1}}))
    FileUtils.cp_r((base + v.fetch('asset')).cleanpath, catalog + 'AppIcon.appiconset') unless (catalog + 'AppIcon.appiconset').exist?
    ref = project.main_group.new_file(catalog.relative_path_from(build).to_s)
    target.resources_build_phase.add_file_reference(ref)
    icon_name = 'AppIcon'
    FileUtils.cp((base + v.fetch('preview')).cleanpath, preview)
  end
  target.resources_build_phase.add_file_reference(project.main_group.new_file(preview.relative_path_from(build).to_s))
  plist = build + 'Info' + "#{v.fetch('id')}.plist"
  Xcodeproj::Plist.write_to_path({
    'CFBundleDisplayName' => v.fetch('label'),
    'CFBundleName' => '$(PRODUCT_NAME)',
    'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
    'CFBundlePackageType' => 'APPL',
    'CFBundleShortVersionString' => '1.0',
    'CFBundleVersion' => v.fetch('build', '1'),
    'LSRequiresIPhoneOS' => true,
    'UILaunchScreen' => {},
    'UIApplicationSceneManifest' => {'UIApplicationSupportsMultipleScenes' => false},
    'UISupportedInterfaceOrientations' => ['UIInterfaceOrientationPortrait'],
    'ComparisonTitle' => v.fetch('title'),
    'ComparisonDescription' => v.fetch('description'),
    'ComparisonPreview' => v.fetch('id')
  }, plist.to_s)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'ASSETCATALOG_COMPILER_APPICON_NAME' => icon_name,
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_IDENTITY[sdk=iphoneos*]' => 'Apple Development',
      'DEVELOPMENT_TEAM' => ENV.fetch('SURROUND_ICON_TEAM', '269H7P4WSN'),
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.honganhkhoa.Surround.IconStudy.#{v.fetch('id')}",
      'PRODUCT_NAME' => v.fetch('target'),
      'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'INFOPLIST_FILE' => plist.relative_path_from(build).to_s,
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'SUPPORTS_MACCATALYST' => 'NO',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
      'SDKROOT' => 'iphoneos',
      'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator'
    })
  end
end
project.save
project.targets.each do |target|
  single = Xcodeproj::XCScheme.new
  single.add_build_target(target)
  single.set_launch_target(target)
  single.save_as(project.path, target.name, true)
end
scheme = Xcodeproj::XCScheme.new
project.targets.each { |target| scheme.add_build_target(target) }
scheme.set_launch_target(project.targets.last)
scheme.save_as(project.path, 'All Icons', true)
puts "Generated #{project.path} with #{project.targets.count} comparison targets."
