#!/usr/bin/env ruby
# Registers every LogYourBodyTests/*.swift file into the LogYourBodyTests target.
# Idempotent: skips files already in the sources build phase.
require "xcodeproj"

project_path = File.expand_path("../LogYourBody.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == "LogYourBodyTests" } or abort "target not found"
tests_dir = File.expand_path("../LogYourBodyTests", __dir__)

group = project.main_group.find_subpath("LogYourBodyTests", true)
group.set_source_tree("<group>")
group.set_path("LogYourBodyTests")

existing = target.source_build_phase.files.map { |f| f.file_ref&.path&.split("/")&.last }.compact
added = []

Dir[File.join(tests_dir, "*.swift")].sort.each do |file|
  name = File.basename(file)
  next if existing.include?(name)
  ref = group.files.find { |f| f.path == name } || group.new_reference(name)
  target.add_file_references([ref])
  added << name
end

project.save
puts "Added #{added.size} files:"
added.each { |n| puts "  #{n}" }
