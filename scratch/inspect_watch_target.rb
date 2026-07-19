require 'xcodeproj'
p = Xcodeproj::Project.open("ios/Runner.xcodeproj")
t = p.targets.find{|x| x.name == "WatchApp"}
puts "Target name: #{t.name}"
puts "Product type: #{t.product_type}"
puts "Product name: #{t.product_name}"
puts "Product reference path: #{t.product_reference.path}"
puts "Product reference name: #{t.product_reference.name}"
puts "Dependencies: #{t.dependencies.map{|d| d.target.name if d.target}}"
