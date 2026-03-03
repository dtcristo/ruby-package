raise 'Ruby 4.0+ is required for Rb::Package' if RUBY_VERSION.to_f < 4.0

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

    def self.gem_require_paths(name, visited = Set.new)
      return [] if visited.include?(name)

      visited << name
      spec = Gem::Specification.find_by_name(name)
      paths = spec.full_require_paths.dup
      spec.runtime_dependencies.each do |dep|
        paths.concat(gem_require_paths(dep.name, visited))
      end
      paths
    rescue Gem::MissingSpecError
      []
    end

    def self.extract_exports(box)
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
      def import(path)
        box = Ruby::Box.new
        box.require(__FILE__)

        # Resolve relative/absolute file paths; fall back to gem name lookup
        expanded = File.expand_path(path, Dir.pwd)
        if File.exist?(expanded) || File.exist?("#{expanded}.rb")
          box.require(expanded)
        else
          # Gem import: inject transitive load paths into the box first
          Rb::Package
            .gem_require_paths(path)
            .each { |p| box.eval("$LOAD_PATH << #{p.inspect}") }
          box.require(path)
        end

        Rb::Package.extract_exports(box)
      end

      def import_relative(path)
        caller_dir = File.dirname(caller_locations(1, 1).first.path)
        absolute_path = File.expand_path(path, caller_dir)

        box = Ruby::Box.new
        box.require(__FILE__)
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

          # Inject deconstruct_keys and fetch methods to the Exports module
          # Pass the original exports hash for fetch operations
          Rb::Package.inject_methods(exports_module, value)

          Rb::Package.const_set(:Exports, exports_module)
        else
          # Single exports
          Rb::Package.const_set(:EXPORT, value)
        end
      end
    end
  end
end

# Inject only the Kernel module into Kernel
Kernel.prepend(Rb::Package::Kernel)
