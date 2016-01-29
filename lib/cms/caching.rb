module Cms
  module Caching
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
    end

    module InstanceMethods
      def cacheable?
        self.class.cacheable?
      end

      def cached?
        File.exists?(self.full_cache_path)
      end

      def clear_cache(include_dependencies = true)
        # _get_action_controller.expire_page(self.cache_path)
        # if include_dependencies && cache_dependencies.present?
        #   cache_dependencies.each do |dep|
        #     _get_action_controller.expire_page(dep.cache_path)
        #   end
        # end
        instances = cache_instances.try(:uniq)
        if instances.present?
          instances.each do |instance|
            if instance.is_a?(Array) || instance.is_a?(ActiveRecord::Relation)
              instance.all.each do |child|
                paths = child.cache_path
                paths.each do |path|
                  _get_action_controller.expire_page(path)
                end
              end
            else
              paths = instance.cache_path
              paths.each do |path|
                _get_action_controller.expire_page(path)
              end
            end
          end
        end
      end

      def cache_dependencies
        []
      end

      def cache_instances
        [self]
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

      def has_format?
        Rails.application.routes.recognize_path(url)[:format].present?
      end

      def cache_path(url = nil, formats = [:html, :json])
        url ||= self.url
        if !url
          return []
        end
        path = url

        paths = []

        if url == "/" || url == ""
          formats.each do |format|
            paths << "index.#{format}"
          end
        elsif !has_format?
          formats.each do |format|
             paths << path + ".#{format}"
          end
        end


        paths
      end



      def full_cache_path(url = nil)
        path = cache_path(url)
        cache_dir = Rails.application.root.join("public")
        "#{cache_dir}#{path}"
      end
    end
  end
end