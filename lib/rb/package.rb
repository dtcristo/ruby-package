raise 'Ruby 4.0+ is required for Rb::Package' if RUBY_VERSION.to_f < 4.0

module Rb
  module Package
    def import(path)
      box = Ruby::Box.new
      box.require(__FILE__)

      # Resolve relative/absolute file paths; fall back to gem name lookup
      expanded = File.expand_path(path, Dir.pwd)
      if File.exist?(expanded) || File.exist?("#{expanded}.rb")
        box.require(expanded)
      else
        # Gem import: inject transitive load paths into the box first
        gem_require_paths(path).each do |p|
          box.eval("$LOAD_PATH << #{p.inspect}")
        end
        box.require(path)
      end

      begin
        exports = box.const_get(:EXPORTS)
        process_exports(exports)
      rescue NameError
        # Legacy package/ with no EXPORTS — build a lazy proxy module
        build_legacy_proxy(box)
      end
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

      # Sets the EXPORTS constant on the Box's isolated Object namespace
      Object.const_set(:EXPORTS, value)
    end

    private

    def gem_require_paths(name, visited = Set.new)
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

    def build_legacy_proxy(box)
      Module.new do
        @box = box

        # Lazily resolve any constant defined inside the box
        def self.const_missing(name)
          @box.const_get(name)
        rescue NameError
          raise NameError, "uninitialized constant #{name}"
        end

        # Singleton methods/values: delegate via eval inside the box
        def self.method_missing(name, *args, **kw, &blk)
          @box.eval(name.to_s)
        rescue NameError, NoMethodError
          super
        end

        def self.respond_to_missing?(name, include_private = false)
          true
        end

        # Pattern matching destructuring
        def self.deconstruct_keys(keys)
          return {} unless keys

          keys.each_with_object({}) do |key, hash|
            name = key.to_s
            hash[key] = if name.match?(/\A[A-Z]/)
              begin
                @box.const_get(name)
              rescue NameError
                next
              end
            else
              begin
                @box.eval(name)
              rescue NameError, NoMethodError
                next
              end
            end
          end
        end
      end
    end

    def process_exports(exports)
      if exports.is_a?(Hash)
        Module.new do
          const_set(:EXPORTS, exports)
          private_constant :EXPORTS

          exports.each do |k, v|
            if k.to_s.match?(/^[A-Z]/)
              # Capitalized keys become Constants
              const_set(k, v)
            else
              # Lowercase keys become Singleton Methods
              define_singleton_method(k) do |*args, **kw, &blk|
                v.respond_to?(:call) ? v.call(*args, **kw, &blk) : v
              end
            end
          end

          # Implement `#deconstruct_keys` to enable Ruby Pattern Matching
          def self.deconstruct_keys(keys)
            module_exports = const_get(:EXPORTS)
            keys ? module_exports.slice(*keys) : module_exports
          end
        end
      else
        # Single export just returns the object directly
        exports
      end
    end
  end
end

# Inject the module into Kernel
Kernel.prepend(Rb::Package)
