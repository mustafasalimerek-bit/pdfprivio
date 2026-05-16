#!/usr/bin/env ruby
# Programmatically add the PDFPrivioWidget target to Runner.xcodeproj.
# Idempotent — safe to run multiple times. Run from ios/ folder.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('Runner.xcodeproj', __dir__)
WIDGET_NAME = 'PDFPrivioWidget'
WIDGET_BUNDLE_ID = 'com.erekstudio.pdfprivio.PDFPrivioWidget'
APP_GROUP_ID = 'group.com.erekstudio.pdfprivio'

project = Xcodeproj::Project.open(PROJECT_PATH)

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' if runner_target.nil?

widget_target = project.targets.find { |t| t.name == WIDGET_NAME }
if widget_target
  puts "Widget target already exists, skipping target creation."
else
  widget_target = project.new_target(
    :app_extension,
    WIDGET_NAME,
    :ios,
    '17.0',
    nil,
    :swift
  )

  widget_target.build_configurations.each do |config|
    config.build_settings.merge!(
      'INFOPLIST_FILE' => 'PDFPrivioWidget/Info.plist',
      'PRODUCT_BUNDLE_IDENTIFIER' => WIDGET_BUNDLE_ID,
      'CODE_SIGN_ENTITLEMENTS' => 'PDFPrivioWidget/PDFPrivioWidget.entitlements',
      'SWIFT_VERSION' => '5.0',
      'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'CURRENT_PROJECT_VERSION' => '2',
      'MARKETING_VERSION' => '1.0.0',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'SKIP_INSTALL' => 'YES',
      'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
      'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
      'ENABLE_PREVIEWS' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
      'MTL_FAST_MATH' => 'YES'
    )
  end

  widget_group = project.main_group.new_group(WIDGET_NAME, WIDGET_NAME)

  swift_ref = widget_group.new_reference('PDFPrivioWidget.swift')
  widget_target.source_build_phase.add_file_reference(swift_ref, true)

  widget_group.new_reference('Info.plist')

  assets_ref = widget_group.new_reference('Assets.xcassets')
  widget_target.resources_build_phase.add_file_reference(assets_ref, true)

  widget_group.new_reference('PDFPrivioWidget.entitlements')

  embed_phase = runner_target.copy_files_build_phases.find do |phase|
    phase.symbol_dst_subfolder_spec == :plug_ins
  end
  embed_phase ||= begin
    p = runner_target.new_copy_files_build_phase('Embed App Extensions')
    p.symbol_dst_subfolder_spec = :plug_ins
    p
  end
  embed_file = embed_phase.add_file_reference(widget_target.product_reference, true)
  embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  # Move Embed App Extensions BEFORE the [CP] script phases. Flutter +
  # CocoaPods otherwise produces a dependency cycle (Info.plist needs
  # the embedded widget, but Thin Binary / [CP] scripts run after the
  # embed by default). Standard Apple placement: right after Resources.
  resources_idx = runner_target.build_phases.find_index do |p|
    p.is_a?(Xcodeproj::Project::PBXResourcesBuildPhase)
  end
  if resources_idx
    runner_target.build_phases.delete(embed_phase)
    runner_target.build_phases.insert(resources_idx + 1, embed_phase)
  end

  runner_target.add_dependency(widget_target)

  puts "Created widget target: #{WIDGET_NAME}"
end

# Always (re)configure Runner entitlements path
runner_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

runner_group = project.main_group.find_subpath('Runner')
if runner_group && !runner_group.children.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
  puts "Added Runner.entitlements to Runner group."
end

project.save

puts "Targets after save: #{project.targets.map(&:name).join(', ')}"
