require "cms/engine"
require "cms/version"
require 'cms/config'
require 'cms/object_extensions'
require 'cms/utils'
require 'cms/active_record_extensions'
require 'cms/action_mailer_extensions'
require 'cms/migration_extensions'
require 'cms/activerecord_migration_columns'

#require 'cms/page'
require 'cms/pages'
require 'cms/json_data'
#require 'cms/meta_tags'
#require 'cms/sitemap_record'
#require 'cms/html_block'
#require 'cms/keyed_html_block'
#require 'cms/banner'
#require 'cms/form_config'

require 'cms/caching'
require 'cms/helpers/cache_naming_helper'

require 'cms/helpers/pages_helper'
require 'cms/helpers/meta_data_helper'
require 'cms/helpers/navigation_helper'
require 'cms/helpers/action_view_url_helper'
require 'cms/helpers/action_view_cache_helper'
require 'cms/helpers/image_helper'
require 'cms/helpers/url_helper'
require 'cms/helpers/forms_helper'

require 'cms/app_router'
require 'cms/page_url_helpers'
require 'cms/resource_navigation'
require 'cms/human_attribute_name'



require "cms/active_record_helpers"

require 'cms/paperclip_extension'
require 'cms/globalize_extension'

require 'cms/articles/activerecord_migrations'
require 'cms/articles/activerecord_helpers'

require 'cms/banners/activerecord_helpers'
require 'cms/banners/activerecord_migrations'
require 'cms/banners/owner_methods'

require 'cms/content_blocks/activerecord_helpers'
require 'cms/content_blocks/activerecord_migrations'
#require 'cms/banners/owner_methods'

require 'cms/ecommerce'


require 'rails_admin_extensions/config'
require 'rails_admin_extensions/custom_fields'
#require 'rails_admin_extensions/rails_admin_props'


require 'cms/router_extensions/domain_constraint'
require 'cms/router_extensions/host_constraint'
require 'cms/router_extensions/mapper'

module Cms
  class << self
    def pages_models
      Dir[Rails.root.join("app/models/pages/*")].map{|p| filename = File.basename(p, ".rb"); "Pages::" + filename.camelize }
    end

    def templates_models
      Dir[Rails.root.join("app/models/templates/*")].map{|p| filename = File.basename(p, ".rb"); "Templates::" + filename.camelize }
    end

    def config(&block)
      config_class = Cms::Config
      if block_given?
        config_class.instance_eval(&block)
      end

      return config_class
    end

    def configure_rails_admin(config)
      models = [Cms::MetaTags]
      config.include_pages_models
      config.include_models(*models)

      models.each do |m|

        m.configure_rails_admin(config)
      end

      if Cms.config.use_translations && Cms::Page.respond_to?(:translation_class)
        config.model Cms::Page.translation_class do
          visible false
        end
      end
    end

    def t(*args)
      text_model = Text rescue nil
      str = nil
      str = text_model.t(*args) if text_model
      #options = args.extract_options!
      keys = args.select{|key|
        match = key.is_a?(String) || key.is_a?(Symbol)

        if match
          next true
        else
          break false
        end
      }




      if str.blank?
        key = args.shift
        options = args.select{|a| break true if a.is_a?(Hash); next false }.first || {}
        if options.nil? || !options.is_a?(Hash)
          options = {}
        end

        updated_options = options.merge({raise: true})
        arguments = [key, updated_options]

        begin
          str = I18n.t(*arguments)
        rescue
          if text_model
            ignore_scopes = ["activerecord", "rails_admin", "admin", "page_titles"]
            if !key.to_s.split(".").first.in?(ignore_scopes)
              text_model.create(key: key, generated: true) rescue nil
              text_model.load_translations(true)
            end

          end
          next_key_args = args
          next_keys = args.select{|a| break false if a.is_a?(Hash); next true }
          str = t(*next_key_args, options) if str.blank? && next_keys.any?
          str = key.split(".").last.to_s.humanize
        end
      end








      str.to_s.html_safe
    end


  end
end

include_caching_to_models = true
# if include_caching_to_models
#   c = ActiveRecord::Base
#   c.send :include, Cms::PageUrlHelpers
#   c.send :extend, Cms::Caching::ClassMethods
#   c.send :include, Cms::Caching::InstanceMethods
# end

