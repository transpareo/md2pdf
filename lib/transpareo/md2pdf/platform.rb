# frozen_string_literal: true

require 'rbconfig'

module Transpareo
  module Md2pdf
    # Detects the running OS and CPU so the installer can pick the
    # right prebuilt archive, and so `doctor` can print an install
    # hint that matches the user's package manager.
    module Platform
      # Maps our platform key to the slug used in Chrome for Testing
      # download URLs.
      CHROME_SLUGS = {
        %i[linux x86_64] => 'linux64',
        %i[macos x86_64] => 'mac-x64',
        %i[macos arm64] => 'mac-arm64',
      }.freeze

      module_function

      def os
        case RbConfig::CONFIG['host_os']
        when /linux/ then :linux
        when /darwin/ then :macos
        when /mswin|mingw|cygwin/ then :windows
        else :unknown
        end
      end

      def arch
        case RbConfig::CONFIG['host_cpu']
        when /x86_64|amd64/ then :x86_64
        when /arm64|aarch64/ then :arm64
        else :unknown
        end
      end

      def key
        [os, arch]
      end

      def chrome_slug
        CHROME_SLUGS[key]
      end

      # The prebuilt Chrome archives link against glibc, so musl
      # systems (Alpine) have to use distro packages instead.
      def musl?
        return true if File.exist?('/etc/alpine-release')

        Dir.glob('/lib/ld-musl-*.so.1').any?
      end

      # Coarse distro family, used only to pick an install hint.
      def linux_family
        return nil unless os == :linux

        release = read_os_release
        ids = "#{release['ID']} #{release['ID_LIKE']}"
        case ids
        when /arch|manjaro/ then :arch
        when /alpine/ then :alpine
        when /fedora|rhel|centos/ then :fedora
        # Ubuntu is not Debian for this purpose: it has no chromium
        # package, only a chromium-browser that is a transitional
        # shim pulling in snapd and a confined browser.
        when /ubuntu/ then :ubuntu
        when /debian/ then :debian
        else :unknown
        end
      end

      def read_os_release
        return {} unless File.readable?('/etc/os-release')

        File.readlines('/etc/os-release').each_with_object({}) do |l, h|
          k, v = l.strip.split('=', 2)
          h[k] = v.to_s.delete('"') if k && v
        end
      rescue SystemCallError
        {}
      end
    end
  end
end
