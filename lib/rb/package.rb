raise 'Ruby 4.0+ is required for Rb::Package' if RUBY_VERSION.to_f < 4.0
require 'tempfile'

# Global registry of boxes created by import/import_relative. Kept alive here
# to prevent Ruby::Box GC crashes when boxes that loaded native-extension gems
# (e.g. faker → concurrent-ruby) are collected during process exit. Using a
# global ensures boxes created inside child boxes register with the same list.
# Globals are process-wide in Ruby::Box (they do not leak *between* boxes, but a
# child box can read/write the outer process's globals). This does NOT leak
# between unrelated Ruby processes; Ruby::Box prevents that.
$rb_package_boxes ||= []

module Rb
  module Package
    def self.inject_methods(obj, exports_map = nil, box = nil)
      # Use a local variable to capture exports_map in the closures
      exports_data = exports_map

      obj.define_singleton_method(:deconstruct_keys) do |keys|
        return {} unless keys

        keys.each_with_object({}) do |key, hash|
          name = key.to_s
          hash[key] = if exports_data
            exports_data[key.to_sym] || exports_data[key.to_s]
          elsif box
            if name.match?(/\A[A-Z]/)
              begin
                box.const_get(name)
              rescue NameError
                next
              end
            else
              begin
                box.eval(name)
              rescue NameError, NoMethodError
                next
              end
            end
          end
        end
      end

      obj.define_singleton_method(:fetch) do |*keys|
        key = keys.first
        name = key.to_s

        if exports_data
          exports_data[key.to_sym] || exports_data[key.to_s]
        elsif box
          if name.match?(/\A[A-Z]/)
            begin
              box.const_get(name)
            rescue NameError
              nil
            end
          else
            begin
              box.eval(name)
            rescue NameError, NoMethodError
              nil
            end
          end
        end
      end

      obj.define_singleton_method(:fetch_values) do |*keys|
        keys.map { |key| fetch(key) }
      end
    end

    def self.seed_box_load_path(box, paths)
      # box.eval("$LOAD_PATH.unshift(p)") only modifies the Ruby-level $LOAD_PATH
      # Array object inside the box. The C-level $LOAD_PATH (searched by require)
      # is only updated when code runs as native box code via box.require(file).
      # We write a temp file containing the unshift calls and require it so that
      # the seeding happens in the box's native execution context.
      tmp = Tempfile.new(['rb_pkg_lp_', '.rb'])
      begin
        paths.each { |p| tmp.puts("$LOAD_PATH.unshift(#{p.inspect}) unless $LOAD_PATH.include?(#{p.inspect})") }
        tmp.close
        box.require(tmp.path)
      ensure
        tmp.unlink
      end
    end

    def self.extract_exports(box)
      # Each box runs its own isolated copy of Rb::Package, so EXPORT and Exports
      # set by export() inside a box live in that box's namespace and do not leak
      # to any other box or to the outer module. We look up through the box.
      begin
        box::Rb::Package::Exports
      rescue NameError
        begin
          box::Rb::Package::EXPORT
        rescue NameError
          # Bare package/gem with no exports — return the Box instance directly
          inject_methods(box, nil, box)
          box
        end
      end
    end

    module Kernel
      # Capture a reference to the current box's $LOAD_PATH array at definition
      # time. Because Ruby::Box gives each box its own isolated $LOAD_PATH array,
      # this reference points to THIS box's array. When bundler/setup (or any other
      # code) later pushes paths onto the box's $LOAD_PATH, those additions are
      # visible through this reference. Without this capture, reading $LOAD_PATH
      # inside a def-based method always sees the outer process's $LOAD_PATH even
      # when the method is invoked from within a box.
      _lp = $LOAD_PATH

      define_method(:import) do |path|
        box = Ruby::Box.new
        $rb_package_boxes << box  # prevent GC; see comment above
        box.require(__FILE__)

        # Seed the child box's C-level $LOAD_PATH by requiring a temp file that
        # runs $LOAD_PATH.unshift for each path as native box code. box.eval based
        # seeding only modifies the Ruby-level $LOAD_PATH array; the C-level array
        # (searched by require) is only updated when code runs as box-native code
        # via box.require(absolute_file). _lp is a live reference to the defining
        # box's $LOAD_PATH array — bundler/setup paths added after this file loads
        # are included automatically.
        Rb::Package.seed_box_load_path(box, _lp)

        expanded = File.expand_path(path, Dir.pwd)
        if File.exist?(expanded) || File.exist?("#{expanded}.rb")
          box.require(expanded)
        else
          # Resolve gem/package names by searching the defining box's $LOAD_PATH
          # for the entry file and using an absolute path with box.require.
          resolved = _lp.lazy.flat_map { |dir|
            ["#{dir}/#{path}.rb", "#{dir}/#{path}"]
          }.find { |f| File.exist?(f) }
          box.require(resolved || path)
        end

        Rb::Package.extract_exports(box)
      end

      define_method(:import_relative) do |path|
        caller_dir = File.dirname(caller_locations(1, 1).first.path)
        absolute_path = File.expand_path(path, caller_dir)

        box = Ruby::Box.new
        $rb_package_boxes << box  # prevent GC; see comment above
        box.require(__FILE__)

        # Same C-level $LOAD_PATH seeding as import above.
        Rb::Package.seed_box_load_path(box, _lp)

        box.require(absolute_path)

        Rb::Package.extract_exports(box)
      end

      def export(*args, **kwargs)
        value =
          if kwargs.any? && args.empty?
            kwargs # Multiple exports
          elsif args.size == 1 && kwargs.empty?
            args.first # Single export
          else
            raise ArgumentError,
                  'Export takes either a single object or keyword arguments'
          end

        if value.is_a?(Hash)
          # Create Exports module for hash exports
          exports_module = Module.new

          value.each do |k, v|
            if k.to_s.match?(/^[A-Z]/)
              exports_module.const_set(k, v)
            else
              exports_module.define_singleton_method(k) do |*args, **kw, &blk|
                v.respond_to?(:call) ? v.call(*args, **kw, &blk) : v
              end
            end
          end

          Rb::Package.inject_methods(exports_module, value)

          # Rb::Package::Exports does not leak between boxes — see extract_exports.
          Rb::Package.const_set(:Exports, exports_module)
        else
          # Rb::Package::EXPORT does not leak between boxes — see extract_exports.
          Rb::Package.const_set(:EXPORT, value)
        end
      end
    end
  end
end

# Inject only the Kernel module into Kernel
Kernel.prepend(Rb::Package::Kernel)
