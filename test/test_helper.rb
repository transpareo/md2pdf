$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'tmpdir'
require 'md2pdf'

module TestSupport
  module_function

  # True when a working `pandoc` is on PATH; integration tests
  # that shell out to the real filter chain skip without it.
  def pandoc?
    @pandoc = system(
      Md2pdf::PANDOC, '--version',
      out: File::NULL, err: File::NULL
    ) if @pandoc.nil?
    @pandoc
  end
end
