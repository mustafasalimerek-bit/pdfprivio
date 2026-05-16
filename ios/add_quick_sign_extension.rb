#!/usr/bin/env ruby
# Adds the PDFPrivioQuickSign Action Extension target. Mirrors the
# PDFPrivioShare share-extension pattern — pure Swift, no Pods — so
# build stays clean of the receive_sharing_intent integration that
# blocked our earlier attempt.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('Runner.xcodeproj', __dir__)
EXT_NAME = 'PDFPrivioQuickSign'
EXT_BUNDLE_ID = 'com.erekstudio.pdfprivio.PDFPrivioQuickSign'

project = Xcodeproj::Project.open(PROJECT_PATH)

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' if runner_target.nil?

ext_target = project.targets.find { |t| t.name == EXT_NAME }
if ext_target
  puts "PDFPrivioQuickSign target already exists, skipping target creation."
else
  ext_target = project.new_target(
    :app_extension,
    EXT_NAME,
    :ios,
    '15.5',
    nil,
    :swift
  )

  team = runner_target.build_configurations.first.build_settings['DEVELOPMENT_TEAM']

  ext_target.build_configurations.each do |config|
    config.build_settings.merge!(
      'INFOPLIST_FILE' => 'PDFPrivioQuickSign/Info.plist',
      'PRODUCT_BUNDLE_IDENTIFIER' => EXT_BUNDLE_ID,
      'CODE_SIGN_ENTITLEMENTS' => 'PDFPrivioQuickSign/PDFPrivioQuickSign.entitlements',
      'SWIFT_VERSION' => '5.0',
      'IPHONEOS_DEPLOYMENT_TARGET' => '15.5',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'CURRENT_PROJECT_VERSION' => '3',
      'MARKETING_VERSION' => '1.0.0',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'SKIP_INSTALL' => 'YES',
      'DEVELOPMENT_TEAM' => team
    )
  end

  ext_group = project.main_group.new_group(EXT_NAME, EXT_NAME)

  swift_ref = ext_group.new_reference('QuickSignViewController.swift')
  ext_target.source_build_phase.add_file_reference(swift_ref, true)

  ext_group.new_reference('Info.plist')
  ext_group.new_reference('PDFPrivioQuickSign.entitlements')

  storyboard_group = ext_group.new_group('Base.lproj', 'Base.lproj')
  storyboard_ref = storyboard_group.new_reference('MainInterface.storyboard')
  ext_target.resources_build_phase.add_file_reference(storyboard_ref, true)

  embed_phase = runner_target.copy_files_build_phases.find do |phase|
    phase.symbol_dst_subfolder_spec == :plug_ins
  end
  embed_phase ||= begin
    p = runner_target.new_copy_files_build_phase('Embed App Extensions')
    p.symbol_dst_subfolder_spec = :plug_ins
    p
  end
  embed_file = embed_phase.add_file_reference(ext_target.product_reference, true)
  embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  resources_idx = runner_target.build_phases.find_index do |p|
    p.is_a?(Xcodeproj::Project::PBXResourcesBuildPhase)
  end
  if resources_idx
    runner_target.build_phases.delete(embed_phase)
    runner_target.build_phases.insert(resources_idx + 1, embed_phase)
  end

  runner_target.add_dependency(ext_target)

  puts "Created PDFPrivioQuickSign target with team=#{team}"
end

project.save
puts "Targets: #{project.targets.map(&:name).join(', ')}"
