require 'xcodeproj'
p = Xcodeproj::Project.open("ios/Runner.xcodeproj")
t = p.targets.find{|x| x.name == "Runner"}
t.build_phases.each do |b|
  matching_files = b.files.select { |f| f.file_ref && ((f.file_ref.name && f.file_ref.name.include?("Watch")) || (f.file_ref.path && f.file_ref.path.include?("Watch"))) }.map { |f| f.file_ref.name || f.file_ref.path }
  puts "#{b.isa} (#{b.respond_to?(:name) ? b.name : ''}): #{matching_files}"
end
