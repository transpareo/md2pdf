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

desc 'Render README.md to docs/README.pdf and refresh the screenshot'
task :readme_pdf do
  require 'fileutils'
  require_relative 'lib/transpareo/md2pdf'

  FileUtils.mkdir_p('docs')

  # Badges, the screenshot and the caption about it are stripped:
  # they are remote, self-referential, or commentary on an image
  # this document does not contain. A PDF that silently depends on
  # the network is not a good demonstration of anything either.
  source = File.read('README.md')
    .gsub(/^\[!\[.*?\]\(.*?\)\]\(.*?\)$\n/, '')
    .gsub(/^!\[[^\]]*\]\([^)]*\)$\n/m, '')
    .sub(/^\[\*\*See this README.*?\n\n/m, '')
    .sub(%r{^<sub>.*?</sub>\n\n}m, '')

  Dir.mktmpdir do |dir|
    md = File.join(dir, 'README.md')
    File.write(md, source)
    # This file is code-dense, so its prose word count lands under
    # the default threshold and the TOC would be auto-skipped. The
    # demo is more useful with one, so ask for it explicitly.
    #
    # The logo is passed the same way a user would pass their own.
    # It ships in this repository, not in the gem, so an install
    # renders unbranded until someone supplies an asset.
    Transpareo::Md2pdf.convert(
      md,
      output: 'docs/README.pdf',
      toc_min_words: 800,
      logo: File.expand_path('docs/assets/transpareo-logo.svg', __dir__)
    )
  end

  next unless system('pdftoppm', '-v', out: File::NULL, err: File::NULL)

  Dir.mktmpdir do |dir|
    prefix = File.join(dir, 'page')
    sh 'pdftoppm', '-png', '-r', '130', '-f', '1', '-l', '4',
       'docs/README.pdf', prefix
    tiles = Dir[File.join(dir, 'page-*.png')]
    sh 'montage', *tiles, '-tile', "#{tiles.size}x1",
       '-geometry', '+10+10', '-background', 'none',
       '-bordercolor', '#d8dde3', '-border', '1', 'docs/sample.png'
    sh 'magick', 'docs/sample.png', '-resize', '2000x', '-strip',
       'docs/sample.png'
  end
end

task default: %i[test]
