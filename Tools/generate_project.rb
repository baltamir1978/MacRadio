#!/usr/bin/env ruby
# Generates MacRadio.xcodeproj from scratch: the app, the widget extension and the code they
# share. The project is an output, not a source — edit this script and run it again
# (`ruby Tools/generate_project.rb`) rather than changing target settings in Xcode, or the
# next run will undo them. New .swift files are picked up from their folder automatically.
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PATH = File.join(ROOT, 'MacRadio.xcodeproj')
TEAM = 'JKMR84FU58'
MACOS = '26.0'
VERSION = '1.0'
BUILD = '1'
LANGS = %w[es en fr de pt].freeze

FileUtils.rm_rf(PATH)
project = Xcodeproj::Project.new(PATH)
project.root_object.development_region = 'es'
project.root_object.known_regions = LANGS + ['Base']
project.root_object.attributes['LastUpgradeCheck'] = '2700'

project.build_configurations.each do |config|
  bs = config.build_settings
  bs['MACOSX_DEPLOYMENT_TARGET'] = MACOS
  bs['SWIFT_VERSION'] = '6.0'
  bs['DEVELOPMENT_TEAM'] = TEAM
  # Developer ID, like the other Mac apps: no provisioning profile needed, because the app
  # group carries the team prefix. build.sh signs the same way.
  bs['CODE_SIGN_STYLE'] = 'Manual'
  bs['CODE_SIGN_IDENTITY'] = 'Developer ID Application'
  bs['ENABLE_HARDENED_RUNTIME'] = 'YES'
  bs['MARKETING_VERSION'] = VERSION
  bs['CURRENT_PROJECT_VERSION'] = BUILD
  bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  bs['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  bs['SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY'] = 'YES'
  bs['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
  bs['CLANG_ENABLE_OBJC_ARC'] = 'YES'
end

app = project.new_target(:application, 'MacRadio', :osx, MACOS, nil, :swift)
widget = project.new_target(:app_extension, 'MacRadioWidget', :osx, MACOS, nil, :swift)

# The gem links Cocoa/Foundation with a hard-coded SDK path; Swift autolinks them anyway.
[app, widget].each do |t|
  t.frameworks_build_phase.files.dup.each { |bf| bf.remove_from_project }
end

app.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'Altamirano.MacRadio'
  bs['PRODUCT_NAME'] = 'MacRadio'
  bs['INFOPLIST_FILE'] = 'MacRadio/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'MacRadio/MacRadio.entitlements'
  bs['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  bs['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  bs['COMBINE_HIDPI_IMAGES'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
  # Same isolation default as RadioApp for iOS, so the ported player reads the same.
  bs['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
  # Tells the shared intents they're running next to the player (see PlayerCommand.dispatch).
  bs['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) MACRADIO_APP'
end

widget.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'Altamirano.MacRadio.Widget'
  bs['PRODUCT_NAME'] = 'MacRadioWidget'
  bs['INFOPLIST_FILE'] = 'MacRadioWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'MacRadioWidget/MacRadioWidget.entitlements'
  bs['SKIP_INSTALL'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks',
                                   '@executable_path/../../../../Frameworks']
end

def add_sources(project, folder, targets)
  group = project.main_group.new_group(folder, folder)
  Dir.glob(File.join(ROOT, folder, '*')).sort.each do |file|
    name = File.basename(file)
    ref = group.new_reference(name)
    case File.extname(name)
    when '.swift' then targets.each { |t| t.add_file_references([ref]) }
    when '.xcassets', '.xcprivacy' then targets.each { |t| t.add_resources([ref]) }
    end
  end
  group
end

add_sources(project, 'MacRadio', [app])
add_sources(project, 'MacRadioWidget', [widget])
add_sources(project, 'Shared', [app, widget])

# One set of translations for both bundles: the extension can't read the app's.
loc = project.main_group.new_group('Localization')
variant = loc.new_variant_group('Localizable.strings')
LANGS.each do |lang|
  ref = variant.new_reference("Localization/#{lang}.lproj/Localizable.strings")
  ref.name = lang
end
app.add_resources([variant])
widget.add_resources([variant])

tools = project.main_group.new_group('Tools', 'Tools')
Dir.glob(File.join(ROOT, 'Tools', '*.{rb,swift}')).sort.each { |f| tools.new_reference(File.basename(f)) }

# Embed the widget in the app.
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, nil, launch_target: true)
scheme.save_as(PATH, 'MacRadio', true)

puts "OK: #{project.targets.map(&:name).join(', ')}"
