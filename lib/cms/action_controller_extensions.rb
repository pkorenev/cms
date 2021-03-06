module ActionControllerExtensions
  module ClassMethods
    def reload_text_translations
      if Rails.env.development?
        before_action do
          Cms::Text.load_translations(true)
        end
      end
    end

    def reload_rails_admin_config(models_to_reload = :all)
      if Rails.env.development?
        before_action do
          if admin_panel?
            if models_to_reload == :all
              RailsAdmin::Config.reset
              RailsAdminDynamicConfig.configure_rails_admin
            else
              if models_to_reload.present?
                if !models_to_reload.respond_to?(:each)
                  models_to_reload = [models_to_reload]
                end

                models_to_reload.each do |m|
                  RailsAdmin::Config.reset_model(m)
                  #Object.send(:remove_const, m) if Object.const_defined?(m)
                  #model_base_dir = Rails.root.join("app/models/").to_s
                  #model_path = model_base_dir + m.underscore + ".rb"
                  #load Rails.root.join(model_path)
                end
              end

              RailsAdminDynamicConfig.configure_rails_admin(false)
            end
          end
        end
      end
    end

    def redirect_page_aliases
      before_action do
        #uri = URI.parse(request.url)
        if request.get?
          redirect_url = Cms::PageAlias.resolve_page_redirect_url(request.path)

          if redirect_url.present? && redirect_url != request.path
            redirect_to redirect_url, status: 301
          end
        end
      end
    end

    def skip_all_before_action_callbacks
      _process_action_callbacks.map(&:filter).each do |item|
        begin
          skip_before_action item
        rescue ArgumentError
          puts "WARNING: skip_all_before_action_callbacks: ArgumentError in skip_before_action #{item.inspect}"
        end
      end
    end

    def initialize_locale_links
      before_action :set_locale_links
    end

  end

  module InstanceMethods
    def self.included(base)
      if base.respond_to?(:helper_method)
        methods = [:asset_path, :locale_links]
        base.helper_method *methods
      end
    end

    def asset_path(url)
      ActionController::Base.helpers.asset_path(url)
    end

    def locale_links(skip_blank = true)
      h = @_locale_links
      if skip_blank && h.is_a?(Hash)
        h.keep_if{|locale, url| url.present? }
      elsif h.is_a?(Hash)
         h
      else
        {}
      end
    end
  end

  module MiscInstanceMethods
    def admin_panel?
      admin = params[:controller].to_s.starts_with?("rails_admin")

      return admin
    end

    def root_without_locale
      redirect_to root_path(locale: I18n.locale)
    end

    def set_locale_links(locale_links_or_proc = {}, &block)
      res = {}
      Cms.config.provided_locales.each do |locale|
        if locale_links_or_proc.respond_to?(:call)
          res[locale.to_sym] = locale.call(locale.to_sym)
        elsif block_given?
          res[locale.to_sym] = block.call(locale.to_sym)
        elsif locale_links_or_proc.is_a?(Hash) && locale_links_or_proc[locale.to_sym].present?
          res[locale.to_sym] = locale_links_or_proc[locale.to_sym]
        end

        next if res[locale.to_sym].present?

        url = @page_instance.try do |p|
          begin
            v = p.url(locale)
          rescue ArgumentError
            v = p.url
          end

          v = p.try(:default_url, locale) if v.blank?
          next nil if v.blank?

          v = "/#{v}" if !v.start_with?("/")

          v
        end

        res[locale.to_sym] = url
      end

      @_locale_links = res
    end
  end
end

ActionController::Base.send(:extend, ActionControllerExtensions::ClassMethods)
#ActionController::Base.send(:include, ActionControllerExtensions::InstanceMethods)
ActionController::Base.send(:include, ActionControllerExtensions::MiscInstanceMethods)