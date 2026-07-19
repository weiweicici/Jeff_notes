require 'xcodeproj'

project_path = "ios/Runner.xcodeproj"
project = Xcodeproj::Project.open(project_path)

# 1. Check if WatchApp target already exists
watch_target = project.targets.find { |t| t.name == 'WatchApp' }
ios_target = project.targets.find { |t| t.name == 'Runner' }

if watch_target
  puts "WatchApp target already exists. Updating product type and product name..."
  watch_target.product_type = 'com.apple.product-type.application'
  watch_target.product_name = 'WatchApp'
else
  puts "Creating WatchApp target..."
  
  # Create watchOS target. Product type for watchOS single-target application is com.apple.product-type.application
  watch_target = project.new_target(:watch2_app, 'WatchApp', :watchos, '9.0', project.products_group, :swift)
  watch_target.product_type = 'com.apple.product-type.application'
  watch_target.product_name = 'WatchApp'
  
  puts "WatchApp target created."
end

# 2. Create the file group in the project structure
group = project.main_group.find_subpath('WatchApp', true)
group.clear # Clear existing references to recreate cleanly

# Define files to add
swift_files = [
  'ios/WatchApp/WatchSessionManager.swift',
  'ios/WatchApp/ContentView.swift',
  'ios/WatchApp/WatchAppApp.swift'
]

# Add files to the group and compilation build phase
watch_target.source_build_phase.clear
swift_files.each do |file_path|
  file_ref = group.new_file(File.expand_path(file_path))
  watch_target.add_resources([file_ref]) if file_path.end_with?('.xcassets')
  watch_target.add_file_references([file_ref]) if file_path.end_with?('.swift')
end

# Add Assets
assets_path = 'ios/WatchApp/Assets.xcassets'
assets_ref = group.new_file(File.expand_path(assets_path))
watch_target.add_resources([assets_ref])

# 3. Setup configurations for WatchApp
watch_target.build_configurations.each do |config|
  config.build_settings['SDKROOT'] = 'watchos'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zhenfeng.jeffNotes.watchkitapp'
  config.build_settings['PRODUCT_NAME'] = 'WatchApp'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Jeff Notes'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '9.0'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = 'com.zhenfeng.jeffNotes'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['INFOPLIST_KEY_WKApplication'] = 'YES'
end

# 4. Embed WatchApp target in iOS application (Runner target)
# Find or create Embed Watch Content build phase in iOS target
embed_phase = ios_target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.name == 'Embed Watch Content' }
unless embed_phase
  embed_phase = ios_target.new_copy_files_build_phase('Embed Watch Content')
end
embed_phase.symbol_dst_subfolder_spec = :wrapper
embed_phase.dst_path = 'Watch'

# Clear existing embeds for WatchApp to avoid duplication
existing_build_file = embed_phase.files.find { |f| f.file_ref == watch_target.product_reference }
existing_build_file&.remove_from_project
build_file = embed_phase.add_file_reference(watch_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Reorder build phases to place Embed Watch Content after Resources and before any script phases (to avoid dependency cycle)
resources_index = ios_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
if resources_index
  ios_target.build_phases.delete(embed_phase)
  ios_target.build_phases.insert(resources_index + 1, embed_phase)
end

# 5. Add dependency from Runner target to WatchApp target
unless ios_target.dependencies.any? { |dep| dep.target == watch_target }
  ios_target.add_dependency(watch_target)
end

project.save
puts "Xcode project successfully configured for Apple Watch!"
