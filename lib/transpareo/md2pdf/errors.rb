# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Base class for everything this library raises on purpose.
    class Error < StandardError; end

    # A required external binary could not be found on this system.
    class MissingDependencyError < Error
      attr_reader :dependency

      def initialize(dependency, message = nil)
        @dependency = dependency
        super(message || "#{dependency} not found")
      end
    end

    # A required external binary was found but is too old to use.
    class OutdatedDependencyError < Error
      attr_reader :dependency, :found, :required

      def initialize(dependency, found, required)
        @dependency = dependency
        @found = found
        @required = required
        super(
          "#{dependency} #{found} is too old, need >= #{required}"
        )
      end
    end

    # Chromium exited non-zero, or produced no file, while rendering.
    class ConversionError < Error; end

    # A downloaded archive did not match its expected SHA-256.
    class ChecksumError < Error; end

    # No prebuilt binary exists for the running OS and architecture.
    class UnsupportedPlatformError < Error; end
  end
end
