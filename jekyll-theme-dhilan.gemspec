# frozen_string_literal: true

require File.expand_path("../lib/jekyll-theme-dhilan/constants", __FILE__)

Gem::Specification.new do |spec|

  spec.authors = ["dhilanr"]
  spec.files = `git ls-files -z`.split("\x0").select { |f| f.match(%r!^(_layouts|_includes|_sass|assets|lib|node_modules)/|LICENSE.txt$!i) }
  spec.homepage = "https://github.com/dhilanr"
  spec.license = "MIT"
  spec.name = "jekyll-theme-dhilan"
  spec.summary = "This is Dhilan's theme for Jekyll."
  spec.version = "1.1.0"

  spec.add_runtime_dependency "deep_merge", "1.2.1"
  spec.add_runtime_dependency "jekyll", "4.1.1"
  spec.add_runtime_dependency "sanitize", "5.2.1"

  CS50::PLUGINS.each do |gem, version|
    spec.add_runtime_dependency gem, version
  end

end
