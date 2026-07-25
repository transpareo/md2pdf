# frozen_string_literal: true

require 'rake/testtask'
require 'bundler/gem_tasks'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  # RuboCop is a development-only dependency.
end

desc 'Print SHA-256 sums for the pinned Chromium archives'
task :checksums do
  require 'digest'
  require_relative 'lib/transpareo/md2pdf'

  installer = Transpareo::Md2pdf::Installer
  version = installer::CHROME_VERSION

  Transpareo::Md2pdf::Platform::CHROME_SLUGS.each_value do |slug|
    url = installer.chrome_url(version, slug)
    Dir.mktmpdir do |dir|
      archive = File.join(dir, 'c.zip')
      installer.download(url, archive)
      puts "  '#{slug}' => '#{Digest::SHA256.file(archive).hexdigest}',"
    end
  end
end

task default: %i[test]
