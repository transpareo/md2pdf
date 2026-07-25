# frozen_string_literal: true

require_relative 'test_helper'

# What reaches the published gem, as opposed to what sits in the
# repository for demonstration.
class PackagingTest < Minitest::Test
  def setup
    @spec = Gem::Specification.load(
      File.expand_path('../transpareo-md2pdf.gemspec', __dir__)
    )
  end

  # The sample logo demonstrates the branding options here. Shipping
  # it would brand every install with somebody else's trademark.
  def test_ships_no_demo_assets
    assert_empty @spec.files.grep(%r{\Adocs/})
    assert_empty @spec.files.grep(/\.svg\z/)
  end

  def test_ships_the_library_and_the_executable
    assert_includes @spec.files, 'lib/transpareo/md2pdf.rb'
    assert_includes @spec.files, 'exe/md2pdf'
    assert_equal ['md2pdf'], @spec.executables
  end

  # The stylesheet is not a .rb file, so it needs its own entry in
  # spec.files and has been forgotten before.
  def test_ships_the_stylesheet_template
    assert_includes @spec.files, 'lib/transpareo/md2pdf/style.css.erb'
  end

  def test_ships_the_licence_and_docs
    %w[LICENSE.txt README.md CHANGELOG.md].each do |file|
      assert_includes @spec.files, file
    end
  end

  def test_ships_no_tests_or_build_files
    assert_empty @spec.files.grep(%r{\Atest/})
    assert_empty @spec.files.grep(/Gemfile|Rakefile|Dockerfile/)
  end

  def test_every_runtime_file_actually_exists
    root = File.expand_path('..', __dir__)
    missing = @spec.files.reject { |f| File.file?(File.join(root, f)) }

    assert_empty missing, "listed but absent: #{missing.inspect}"
  end

  def test_declares_a_ruby_requirement_and_licence
    assert_equal 'MIT', @spec.license
    refute_nil @spec.required_ruby_version
  end
end
