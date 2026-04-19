# Monkey-patch FastlaneCore::DeviceManager.simulators so that each Device's
# `os_version` reflects the exact runtime version xcodebuild expects
# (e.g. "26.4.1") instead of the marketing header from `simctl list devices`
# (e.g. "26.4"). fastlane's snapshot action builds its xcodebuild destination
# as `OS=#{device.os_version}`, which fails when the two disagree.
require 'fastlane_core/device_manager'

module FastlaneCore
  class DeviceManager
    class << self
      alias_method :simulators_without_xctrace_os_fix, :simulators unless method_defined?(:simulators_without_xctrace_os_fix)

      def simulators(requested_os_type = "")
        devices = simulators_without_xctrace_os_fix(requested_os_type)
        return devices if devices.nil? || devices.empty?

        @xctrace_os_by_udid ||= begin
          map = {}
          out = `xcrun xctrace list devices 2>&1`
          out.lines.each do |l|
            if (m = l.strip.match(/\(([\d.]+)\)\s+\(([-A-F0-9]+)\)\s*$/))
              map[m[2]] = m[1]
            end
          end
          map
        end

        devices.each do |device|
          next unless device.is_simulator && device.respond_to?(:udid)
          real = @xctrace_os_by_udid[device.udid]
          device.os_version = real if real && device.respond_to?(:os_version=) && device.os_version != real
        end
        devices
      end
    end
  end
end
