#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

widget_target = project.targets.find { |t| t.name == 'Widget' }
unless widget_target
  puts "❌ Widget target not found"
  exit 1
end

widget_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings.delete('PROVISIONING_PROFILE_SPECIFIER')
  config.build_settings['DEVELOPMENT_TEAM'] = 'U78542Q47D'
end

project.save
puts "✅ Widget target signing enabled (Automatic)"
