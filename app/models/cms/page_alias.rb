module Cms
  class PageAlias < ActiveRecord::Base
    self.table_name = :page_aliases

    attr_accessible *attribute_names
    extend Enumerize

    def self.include_translations?
      Cms::Config.use_translations && respond_to?(:translates?)
    end

    if include_translations?
      globalize :urls, translation_table_name: :page_alias_translations
    end
    enumerize :redirect_mode, in: [:redirect_to_home_page, :redirect_to_specified_page], default: :redirect_to_home_page

    boolean_scope :disabled, nil, :enabled
    scope :with_urls, ->(urls = nil) {
      column_name = 'page_alias_translations.urls'
      rel = joins(:translations)
      if urls.nil?
         rel = rel.where("#{column_name} IS NOT NULL AND #{column_name}<>''")
      elsif urls.is_a?(String) || urls.is_a?(Array)
        urls = Array.wrap(urls)

        # array of mutiple conditions
        # urls.map do |url|
        #
        #   url_like_strings = [
        #     # in beginning
        #     "#{url}\r\n%",
        #     # in the end
        #     "%\r\n#{url}",
        #     # in
        #     "%\r\n#{url}\r\n%",
        #     "%\r\n#{url}"
        #   ]
        #   where("#{column_name}=:url OR #{column_name} LIKE ", url: url)
        # end

        query_str = urls.map do |url|
          "page_alias_translations.urls LIKE '%#{url}%'"
        end.join(' OR ')

        rel.where(query_str)
      end

    }
    scope :by_model, ->(*model_class_or_name) do
      model_classes, model_names = Cms::PageAlias.resolve_model_class_names(*model_class_or_name)

      where(page_type: model_names)
    end

    default_scope do
      order('page_aliases.id desc')
    end

    has_link :page

    def self.register_resource_class(klass)
      var_name = :@@_resource_classes
      resource_classes = self.class_variable_get(var_name) || [] rescue []
      resource_classes << klass unless resource_classes.include?(klass)
      self.class_variable_set(var_name, resource_classes)
    end

    def self.registered_resource_classes
      var_name = :@@_resource_classes
      self.class_variable_get(var_name) || [] rescue []
    end

    def self.registered_resource_class?(klass)
      registered_resource_classes.include?(klass)
    end

    def self.resources(filter = true)
      registered_resource_classes.map do |klass|
        rel = klass.all
        if filter
          rel = rel.published if rel.respond_to?(:published)
        end

        rel
      end.flatten
    end

    def self.build_page_alias_for_resources
      resources.each do |resource|
        if !resource.page_alias
          resource.build_page_alias
          exists = Cms::PageAlias.where(page_id: resource.id, page_type: resource.class.name).count > 0
          if !exists
            Cms::PageAlias.create(page_id: resource.id, page_type: resource.class.name)
          end
        end
      end
    end

    def self.resolve_model_class_names(*class_names)
      model_names = []
      model_classes = []
      class_names.flatten.map do |model_class_or_name|
        if model_class_or_name.is_a?(String)
          model = model_class_or_name.constantize
          model_name = model_class_or_name
        elsif model_class_or_name.is_a?(Class)
          model = model_class_or_name
          model_name = model.name
        end

        model_classes << model
        model_names << model_name
      end

      [model_classes, model_names]
    end

    def self.urls_by_page
      current_scope.map do |page_alias|
        page_alias
      end
    end

    def self.resolve_page_alias(input_url)
      page_alias = nil
      page_aliases = Cms::PageAlias.enabled.with_urls(input_url).includes(:translations)
      page_aliases.find do |pa|
        urls = pa.urls

        urls.include?(input_url)
      end
    end

    def self.resolve_page_redirect_url(input_url)
      page_alias = resolve_page_alias(input_url)
      if page_alias.nil?
        return nil
      else
        page_alias.resolve_redirect_url(input_url)
      end
    end

    def urls
      urls_by_locale.values.flatten
    end

    def urls_by_locale
      entries = translations.map do |page_alias_translation|
        translation_urls = Cms::TextFields.get_line_separated_field_value(page_alias_translation, :urls)
        if translation_urls.present?
          [page_alias_translation.locale.to_sym, translation_urls]
        else
          nil
        end
      end.select{|item| !item.nil? }

      Hash[entries]
    end

    def resolve_redirect_url(input_url)
      locale = urls_by_locale.keep_if{|locale, urls|
        urls.include?(input_url)
      }.keys.first

      page_alias.redirect_url(locale)
    end

    def redirect_url(locale = I18n.locale)
      if redirect_mode.to_s == 'redirect_to_home_page'
        Pages.home.url(locale)
      else
        page = page_alias.page

        if !page
          return Pages.home.url(locale)
        end

        if page.respond_to?(:published?)
          if !page.published?
            return Pages.home.url(locale)
          end
        end

        page.url(locale)
      end
    end
  end
end