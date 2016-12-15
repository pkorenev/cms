module Cms
  module Caching
    def self.cached_instances( instances )
      if !instances.is_a?(Array)
        instances = [instances]
      end
      instances.map do |item|
        if item.is_a?(ActiveRecord::Relation)
          next item.to_a
        else
          next item
        end
      end.flatten.select{|page|page.cached? || false}
    end

    module ClassMethods


      def cacheable opts = {}
        self.class_variable_set :@@cacheable, true
        opts[:expires_on] ||= nil


        self.after_create :expire
        self.after_update :expire
        self.after_destroy :expire


      end

      def cacheable_resource opts = {}
        opts[:pages] ||= [:home]
        opts[:pages] ||= []
      end

      def cacheable?
        if !self.class_variable_defined?(:@@cacheable)
          return false
        end
        self.class_variable_get :@@cacheable || false
      end

      def self.depends_on(*keys, **options)

      end

      def cache_instances(&block)
        if block_given?
          class_variable_set(:@@_cache_instances_method, block)
        else
          (class_variable_get(:@@_cache_instances_method) rescue nil) || nil
        end
      end
    end

    module InstanceMethods
      def cacheable?
        self.class.cacheable?
      end

      def cached?
        self.full_cache_path.each do |s|
          return false if File.exists?(s)
        end

        return true
      end

      def calculate_expired_paths(include_dependencies = true, filter_existing = true, **options)
        options[:format] ||= [:html, :json]
        options[:ignore_gzip] ||= false
        expired_pages = []
        expired_fragments = []
        if !include_dependencies
          paths = self.cache_path
          paths.each do |path|
            expired_pages << path
          end
          return
        end


        cache_method = (self.class.class_variable_get(:@@_cache_method) rescue nil) || nil
        if cache_method
          instance_eval(&cache_method)
          expired_pages = pages
          fragments = self.fragments
        else
          instances = cache_instances
          expired_pages = paths_for_instances(instances)
          fragments = cache_fragments.flatten
        end





        if fragments.present?
          fragments.each do |fragment_key|
            expired_fragments << fragment_key
          end
        end

        expired_pages = expired_pages.uniq
        if filter_existing
          public_path = Rails.root.join("public").to_s
          public_path = public_path[0, public_path.length - 1] if public_path.end_with?("/")
          
          expired_pages = expired_pages.map{|p|
            relative_path = p
            relative_path = "/#{p}" if !relative_path.start_with?("/")
            path = "#{public_path}#{relative_path}"

            gzipped_path = "#{path}.gz"
            gzipped_files = Dir[gzipped_path]

            (Dir[path] + gzipped_files).uniq
          }.flatten.map{|s| s.gsub(/\A#{public_path}/, "") }
        end

        filtered_file_names = filter_file_name(expired_pages, options)
        if filtered_file_names
          expired_pages = filtered_file_names
        end

        expired_fragments = expired_fragments.flatten.uniq
        if filter_existing
          expired_fragments = expired_fragments.select{|f| _get_action_controller.fragment_exist?(f) rescue true  }
        end


        {pages: expired_pages, fragments: expired_fragments}
      end

      def symbols_to_page_instances(keys)
        if keys.is_a?(Symbol)
          return Pages.send(keys)
        end
        keys.map{ |k|
          if k.respond_to?(:map)
            next symbols_to_page_instances(k)
          elsif keys.is_a?(Symbol)
            next Pages.send(keys)
          end
        }
      end

      def paths_for_instances(instances, locales = I18n.locale)
        instances = [instances] unless instances.respond_to?(:each)
        instances = instances.uniq.select(&:present?)
        instances = symbols_to_page_instances(instances)
        locales = [locales] if !locales.is_a?(Array)
        expired_pages = []

        if instances.present?
          instances.each do |instance|
            if instance.nil?
              next
            end
            if instance.is_a?(Array) || instance.is_a?(ActiveRecord::Relation)
              items = instance
              items = instance.all if instance.is_a?(ActiveRecord::Relation)
              items.each do |child|
                if child.is_a?(String)
                  expired_pages << child
                  next
                end

                if child.is_a?(Symbol)
                  child = Pages.send(child)
                end

                begin
                  paths = child.cache_path(nil, locales)
                rescue
                  next
                end
                paths.each do |path|
                  expired_pages << path
                end
              end
            else
              if instance.is_a?(String)
                expired_pages << instance
                next
              end

              begin
                paths = instance.cache_path(nil, locales)
              rescue
                next
              end
              paths.each do |path|
                expired_pages << path
              end
            end
          end
        end

        expired_pages
      end

      def pages(keys = nil, locales = Cms.locales, &block)
        cache_pages = (instance_variable_get(:@_cache_pages) rescue []) || []
        if keys.nil? && !block_given?
          return cache_pages
        end



        cache_pages << paths_for_instances(keys, locales)
        cache_pages = cache_pages.uniq.flatten
        instance_variable_set(:@_cache_pages, cache_pages)

        cache_pages
      end

      def fragments(keys = nil, locales = Cms.locales, &block)
        cache_fragments = (instance_variable_get(:@_cache_fragments) rescue []) || []
        if keys.nil? && !block_given?
          return cache_fragments
        end

        cache_fragments << locales.map{|locale| next "#{locale}_#{keys}" if keys.is_a?(String) || keys.is_a?(Symbol); keys.map{|k| "#{locale}_#{k}" } }.flatten
        cache_fragments = cache_fragments.uniq
        instance_variable_set(:@_cache_fragments, cache_fragments)

        cache_fragments
      end

      def filter_file_name(pages, options = {})
        if options[:ignore_gzip] || options[:format]
          gzipped_files = []
          expired_pages = pages.select{|f|
            if options[:ignore_gzip] && f.end_with?(".gz")
              next false
            else
              if options[:format]
                formats = options[:format]
                if !formats.is_a?(Array)
                  format = formats
                  next f.end_with?(".#{format}")
                else
                  next formats.any?{|format| f.to_s.end_with?(format.to_s) }
                end
              end
            end
          }

          return expired_pages
        else
          return false
        end


      end

      def clear_cache(*args)
        # _get_action_controller.expire_page(self.cache_path)
        # if include_dependencies && cache_dependencies.present?
        #   cache_dependencies.each do |dep|
        #     _get_action_controller.expire_page(dep.cache_path)
        #   end
        # end

        paths = calculate_expired_paths(*args)
        pages = paths[:pages]
        pages.each do |path|
          _get_action_controller.expire_page(path) rescue nil
        end

        fragments = paths[:fragments]
        fragments.each do |fragment_key|
          _get_action_controller.expire_fragment(fragment_key)
        end

      end

      def cache_dependencies
        []
      end

      def cache_instances
        [self]
      end

      def cache_fragments
        []
      end

      def expired_urls

      end

      def expired_instances

      end

      def expired?
        !cached?
      end

      def expire
        clear_cache
      end

      def url_helpers
        @_url_helpers = Rails.application.routes.url_helpers
      end

      def _get_action_controller
        @_action_controller ||= ActionController::Base.new
      end

      def expire_fragment key, options = nil
        _get_action_controller.expire_fragment(key, options)
      end

      def expire_page options = {}
        _get_action_controller.expire_page(options)
      end

      def has_format?(url = nil)
        url ||= self.url
        Rails.application.routes.recognize_path(url)[:format].present?
      end

      def cache_path(url = nil, locales = I18n.locale, formats = [:html, :json])
        if locales.respond_to?(:count) && locales.count > 1
          return locales.map{|locale| cache_path(url, locale, formats) }.flatten
        end

        url ||= self.url(locales)
        if !url
          return []
        end
        path = url

        paths = []

        if url == "/" || url == ""
          formats.each do |format|
            paths << "index.#{format}"
          end
        elsif !has_format?(url)
          formats.each do |format|
             paths << path + ".#{format}"
          end
        else
          paths << path
        end


        paths
      end



      def full_cache_path(url = nil)
        path = cache_path(url)
        cache_dir = Rails.application.public_path rescue Rails.public_path

        [path].flatten.map{|s| cache_dir.join(s) }
      end
    end
  end
end
