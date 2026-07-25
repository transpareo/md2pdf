# frozen_string_literal: true

require_relative 'lib/transpareo/md2pdf/version'

Gem::Specification.new do |spec|
  spec.name = 'transpareo-md2pdf'
  spec.version = Transpareo::Md2pdf::VERSION
  spec.authors = ['Andre Pankratz']
  spec.email = ['claude@punkrats.com']

  spec.summary = 'Convert markdown to polished PDFs via headless Chromium'
  spec.description = <<~TEXT
    Renders markdown to PDF through a headless browser, so tables,
    code blocks and CSS behave the way they do on the web. Supports
    a resolved-page-number table of contents, footnotes with
    deduplication, locale-aware labels, SVG branding and per-project
    configuration files.
  TEXT

  spec.homepage = 'https://github.com/transpareo/md2pdf'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir[
    'lib/**/*.rb',
    'lib/**/*.erb',
    'exe/*',
    'LICENSE.txt',
    'README.md',
    'CHANGELOG.md'
  ]
  spec.bindir = 'exe'
  spec.executables = ['md2pdf']
  spec.require_paths = ['lib']

  spec.add_dependency 'commonmarker', '~> 2.0'
  spec.add_dependency 'nokogiri', '~> 1.16'
  spec.add_dependency 'pdf-reader', '~> 2.12'
  spec.add_dependency 'rouge', '~> 4.2'
  spec.add_dependency 'rubyzip', '~> 2.3'

  # Leads with `doctor` rather than `install-deps`: most machines
  # already have a browser, and this string is fixed at build time
  # so it cannot tell which case the reader is in.
  spec.post_install_message = <<~MESSAGE
    md2pdf renders through headless Chromium, the one program it
    cannot ship itself.

      md2pdf doctor        see what this machine already has
      md2pdf install-deps  fetch a known-good build (no root)
  MESSAGE
end
