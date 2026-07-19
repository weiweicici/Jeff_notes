require 'xcodeproj'

project_path = "ios/Runner.xcodeproj"
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  puts "Target: #{target.name}"
  puts "  Product Type: #{target.product_type}"
  puts "  Dependencies:"
  target.dependencies.each do |dep|
    dep_name = dep.target ? dep.target.name : (dep.name || "Unknown")
    puts "    - #{dep_name} (Proxy: #{dep.target_proxy})"
  end
  puts "  Build Phases:"
  target.build_phases.each do |phase|
    puts "    - #{phase.class.name.split('::').last} (Name: #{phase.name})"
    if phase.respond_to?(:files)
      phase.files.each do |f|
        if f.file_ref
          file_name = f.file_ref.name || f.file_ref.path || "Unknown"
          puts "      * File Ref: #{file_name}"
        end
      end
    end
  end
  puts "-" * 40
end
