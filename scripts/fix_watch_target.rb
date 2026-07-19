require 'xcodeproj'

project_path = "ios/Runner.xcodeproj"
project = Xcodeproj::Project.open(project_path)

# 1. Find targets
runner_target = project.targets.find { |t| t.name == 'Runner' }
watch_app_target = project.targets.find { |t| t.name == 'WatchApp Watch App' }
legacy_container_target = project.targets.find { |t| t.name == 'WatchApp' }

unless runner_target && watch_app_target
  puts "Error: Runner or WatchApp Watch App target not found."
  exit 1
end

# 2. Delete legacy target if it exists
if legacy_container_target
  puts "Removing legacy container target: WatchApp"
  project.targets.delete(legacy_container_target)
  runner_target.dependencies.delete_if { |dep| dep.target == legacy_container_target }
end

# 3. Configure WatchApp Watch App
puts "Configuring build settings for WatchApp Watch App..."
watch_app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zhenfeng.jeffNotes.watchkitapp'
  config.build_settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = 'com.zhenfeng.jeffNotes'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_WKApplication'] = 'YES'
  config.build_settings['INFOPLIST_KEY_WKWatchOnly'] = 'NO'
  config.build_settings['SDKROOT'] = 'watchos'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '9.0'
  config.build_settings['DEVELOPMENT_TEAM'] = 'U78542Q47D'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

# 4. Ensure Runner target depends on WatchApp Watch App
unless runner_target.dependencies.any? { |dep| dep.target == watch_app_target }
  puts "Adding target dependency from Runner to WatchApp Watch App"
  runner_target.add_dependency(watch_app_target)
end

# 5. Embed WatchApp Watch App in Runner
embed_phase = runner_target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.name == 'Embed Watch Content' }
unless embed_phase
  puts "Creating Embed Watch Content build phase in Runner..."
  embed_phase = runner_target.new_copy_files_build_phase('Embed Watch Content')
end
embed_phase.symbol_dst_subfolder_spec = :wrapper
embed_phase.dst_path = 'Watch'

# Clear existing files in Runner's Embed phase
embed_phase.files.clear

# Add WatchApp Watch App's product reference to Runner's Embed phase
build_file = embed_phase.add_file_reference(watch_app_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Reorder build phases in Runner
resources_index = runner_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
if resources_index
  runner_target.build_phases.delete(embed_phase)
  runner_target.build_phases.insert(resources_index + 1, embed_phase)
end

project.save
puts "Successfully cleaned up and configured watch targets!"
