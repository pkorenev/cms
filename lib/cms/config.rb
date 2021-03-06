require_relative 'configurable'

module Cms
  class Config
    include Configurable

    register_class_option :default_html_format do
      :html
    end

    register_class_option :use_translations do
      ActiveRecord::Base.respond_to?(:translates?) && Cms.config.provided_locales.count > 1
    end

    register_class_option :provided_locales do
      I18n.available_locales
    end

    register_class_option :visible_locales_for_navigation do
      Cms.config.provided_locales
    end

    register_class_option :clear_cache_for_locales do
      [I18n.locale]
    end

    register_class_option :locale_names do
      {
          ru: "рус",
          uk: "укр",
          en: "eng",
          fr: "fra",
          es: "esp"
      }
    end

    register_class_option :locale_hreflangs do
      {}
    end

    register_class_option :enabled_hreflang_locales do
      Cms.config.provided_locales
    end

    register_class_option :exchange_rate_class do
      false
    end

    register_class_option :weather_data_class do
      false
    end

    register_class_option :file_editor_use_can_can do
      false
    end

    register_class_option :file_editor_clear_cache_method do
      nil
    end

    register_class_option :default_sitemap_priority do
      0.9
    end

    register_class_option :default_sitemap_change_freq do
      :monthly
    end

    register_class_option :sitemap_include_changefreq do
      false
    end

    register_class_option :sitemap_include_priority do
      false
    end

    register_class_option :sitemap_controller do
      nil
    end

    register_class_option :robots_txt_disallowed_locales do
      Cms.config.provided_locales.map(&:to_sym) - Cms.config.visible_locales_for_navigation.map(&:to_sym)
    end

    register_class_option :page_alias_enabled do
      false
    end

    register_class_option :page_alias_blocked_urls do
      provided_locales.map {|locale| "/#{locale}" }
    end

    register_class_option :page_alias_generate_associations do
      false
    end

    register_class_option :default_image_styles do
      { default: '1920x1200>' }
    end

    register_class_option :default_image_styles_enabled do
      false
    end

    [:banner, :form_config, :html_block, :content_block, :meta_tags, :page, :sitemap_element].each do |model_name|
      register_class_option "#{model_name}_class" do

        model_class_name = "Cms::#{model_name.to_s.camelize}"
        #if Object.const_defined?(model_class_name)

        #end

        Object.const_get(model_class_name)

      end
    end

    register_class_option :inline_svg_allow_override_size do
      true
    end

    register_class_option :inline_svg_remove_tags do
      ['title']
    end

    register_class_option :inline_svg_remove_g_tags do
      :without_attributes
    end

    register_class_option :inline_svg_remove_attributes do
      [
         {
           tag: 'svg',
           attributes: ['xmlns:sketch', 'xmlns:xlink']
         }
      ]
    end

    register_class_option :inline_svg_remove_blank_tags do
      ['desc', 'defs']
    end
  end
end

#Cms::Config.init