#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates ios/Runner.xcodeproj for the GardendlessKit architecture:
#  - adds the local GardendlessKit SwiftPM package and its product links
#  - adds the thin host source files to the Runner target
#  - removes legacy native implementation files from the build (files stay
#    on disk for reference until the user approves their deletion)
#
# Run with a Ruby that has the xcodeproj gem (e.g. CocoaPods' bundled gems):
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/<version>/libexec \
#   GEM_PATH="$GEM_HOME:$(ruby -e 'puts Gem.default_dir')" \
#   ruby tool/update_ios_project.rb

require "xcodeproj"

PROJECT_PATH = File.expand_path("../ios/Runner.xcodeproj", __dir__)
LOCAL_PACKAGE_PATH = "GardendlessKit"

KIT_PRODUCTS = %w[
  GardendlessCore
  GardendlessResource
  GardendlessBridge
  GardendlessImport
  GardendlessGPNext
  GardendlessAudio
  GardendlessLogging
].freeze

NEW_SOURCES = %w[GameHostController.swift AudioScriptBridge.swift].freeze

LEGACY_SOURCES = %w[
  GameAudioBridge.swift
  GameNavigationDelegate.swift
  GameResourceLocator.swift
  GameResourceSchemeHandler.swift
  GameScriptBridge.swift
  GameSession.swift
  GameViewController.swift
  GpNextNativeCore.swift
  NativeSfxEngine.swift
  AppLogStore.swift
  JavaScriptArgumentEncoder.swift
  NativeSfxExceptionGuard.h
  NativeSfxExceptionGuard.m
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |candidate| candidate.name == "Runner" }
abort "Runner target not found" unless target

package = project.root_object.package_references.find do |reference|
  reference.respond_to?(:relative_path) &&
    reference.relative_path == LOCAL_PACKAGE_PATH
end
unless package
  package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package.relative_path = LOCAL_PACKAGE_PATH
  project.root_object.package_references << package
end

KIT_PRODUCTS.each do |product_name|
  next if target.package_product_dependencies.any? do |dependency|
    dependency.respond_to?(:product_name) &&
      dependency.product_name == product_name
  end
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product_name
  dependency.package = package
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

runner_group = project.main_group.children.find do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.path == "Runner"
end
abort "Runner group not found" unless runner_group

NEW_SOURCES.each do |name|
  next if target.source_build_phase.files.any? do |build_file|
    build_file.file_ref&.path == name
  end
  file_reference = runner_group.new_file(name)
  target.source_build_phase.add_file_reference(file_reference)
end

removed = []
target.source_build_phase.files.dup.each do |build_file|
  path = build_file.file_ref&.path
  next unless LEGACY_SOURCES.include?(path)

  removed << path
  build_file.remove_from_project
end

legacy_references = runner_group.children.select do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXFileReference) &&
    LEGACY_SOURCES.include?(child.path)
end
legacy_references.each do |reference|
  removed << reference.path
  reference.remove_from_project
end

project.save

puts "Added package: #{LOCAL_PACKAGE_PATH}"
puts "Linked products: #{KIT_PRODUCTS.join(', ')}"
puts "Added sources: #{NEW_SOURCES.join(', ')}"
puts "Removed from build (files kept on disk): #{removed.join(', ')}"
