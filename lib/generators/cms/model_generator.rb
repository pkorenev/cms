require 'rails/generators'
require File.expand_path('../utils', __FILE__)

module Cms
  class ModelGenerator < Rails::Generators::Base
    source_root File.expand_path('../templates', __FILE__)
    include Rails::Generators::Migration
    include Generators::Utils::InstanceMethods
    extend Generators::Utils::ClassMethods


    argument :name, required: true
    argument :attributes, :type => :array, :default => [], :banner => "field[:type][:index] field[:type][:index]"
    class_option :use_translations, type: :boolean, default: true


    def index
      @model_file_name = name.to_s.underscore
      @model_class_name = name.to_s.camelize
      @migration_file_name = "create_#{name.to_s.underscore.pluralize}"
      @migration_class_name = "Create#{name.to_s.camelize.pluralize}"
      @table_name = name.to_s.underscore.pluralize

      create_model_migration
      create_model
      add_model_config_to_rails_admin

    end

    private

    def default_attributes
      {
        name: { type: "string", translates: true},
        url_fragment: { type: "string", translates: true },
        content: {type: "text", translates: true, ui_type: "ck_editor"},
        published: {type: "boolean"},
        sorting_position: {type: "integer"},
        short_description: {type: "text", translates: true},
        description: {type: "text", translates: true},
        image: {type: "image"},
        avatar: {type: "image"},
        release_date: {type: "date"},
        linkable: {type: "linkable"}
      }.map do |attr_key, attr_config|
        attr_config.delete(:translates) unless Cms.config.use_translations

        [attr_key, attr_config]
      end.to_h
    end

    def column_type_aliases
      {
          bool: "boolean",
          int: "integer",
          dt: "datetime"
      }
    end

    def compute_attributes

    end

    def compute_model_config
      computed_attributes = {}
      translated_attribute_names = []
      attributes.each do |input_attr|
        input_attr_parts = input_attr.split(":")
        attr_name = input_attr_parts[0]
        attr_type = input_attr_parts[1]

        attr_config = {type: attr_type, translates: !!Cms.config.use_translations && input_attr_parts.index("t") || nil}
        attr_config = attr_config.keep_if{|k, v| !v.nil? }
        attr_config = (default_attributes[attr_name.to_sym] || {}).merge(attr_config)
        if attr_config[:type] == "t"
          attr_config[:type] = nil
          attr_config[:translates] = !!Cms.config.use_translations
        end
        attr_config[:type] = :string if attr_config[:type].nil?

        if column_type_aliases[attr_config[:type].to_sym]
          attr_config[:type] = column_type_aliases[attr_config[:type].to_sym]
        end

        if attr_config[:translates]
          translated_attribute_names << attr_name.to_sym
        end

        computed_attributes[attr_name.to_sym] = attr_config
      end

      {attributes: computed_attributes, translated_attribute_names: translated_attribute_names}
    end

    def add_model_config_to_rails_admin
      model_config = compute_model_config
      attrs = model_config[:attributes]
      is_resource = !attrs[:url_fragment].nil?
      has_translated_attributes = model_config[:translated_attribute_names].try(:any?)

      ignored_attribute_names = ['sorting_position']

      lines = ['']
      lines << "config.model #{@model_class_name} do"
      lines << '  #navigation_label_key :about_us, 2'
      if attrs[:sorting_position]
        lines << '  nestable_list({position_field: :sorting_position})'
      end

      lines << ''

      attrs.each do |attr_name, attr_config|
        if !attr_config[:translates] && !ignored_attribute_names.index(attr_name.to_s)
          line = "  field :#{attr_name}"
          line += ", :#{attr_config[:ui_type]}" if attr_config[:ui_type].present?
          lines << line
        end
      end

      if has_translated_attributes
        lines << '  field :translations, :globalize_tabs'
      end

      if is_resource
        lines << '  field :seo_tags'
      end

      lines << 'end'

      if has_translated_attributes
        lines << ''
        lines << "config.model_translation #{@model_class_name} do"
        #lines << "  field :locale, :hidden"
        attrs.each do |attr_name, attr_config|
          if attr_config[:translates] && !ignored_attribute_names.index(attr_name.to_s)
            line = "  field :#{attr_name}"
            line += ", :#{attr_config[:ui_type]}" if attr_config[:ui_type].present?
            lines << line
          end
        end
        lines << "end"
      end

      base_indent = '        '
      lines_str = lines.map{|l| l.length > 0 ? base_indent + l : '' }.join("\n") + "\n"
      insert_into_file 'app/models/rails_admin_dynamic_config.rb', lines_str, before: /^      end/
    end

    def create_model
      model_config = compute_model_config
      attrs = model_config[:attributes]
      is_resource = !attrs[:url_fragment].nil?
      lines = []
      lines << "class #{@model_class_name} < ActiveRecord::Base"

      if Rails::VERSION::MAJOR < 5
        lines << "  attr_accessible *attribute_names"
        lines << ""
      end

      if model_config[:translated_attribute_names].try(:any?)
        translated_attribute_names_str = model_config[:translated_attribute_names].map{|attr| ":" + attr.to_s }.join(", ")
        lines << "  globalize #{translated_attribute_names_str}"
        lines << ""
      end

      if attrs[:sorting_position]
        default_scope = "order_by_sorting_position"
      elsif attrs[:release_date]
        default_scope = "order_by_release_date"
      else
        default_scope = "order('id desc')"
      end

      model_config[:attributes].each do |attr_name, attr_config|
        if attr_config[:type] == "boolean"
          lines << "  boolean_scope :#{attr_name}"
        elsif attr_name.to_s == "sorting_position"
          lines << "  scope :order_by_#{attr_name}, -> { order('#{attr_name} asc') }"
        elsif attr_config[:type] == "date"
          lines << "  scope :order_by_#{attr_name}, -> { order('#{attr_name} desc') }"
        end
      end


      if default_scope
        lines << "  default_scope do"
        lines << "    #{default_scope}"
        lines << "  end"
      end

      if is_resource
        lines << ""
        lines << "  has_seo_tags"
        lines << "  has_sitemap_record"
      end

      has_cache = true

      if has_cache
        lines << "  has_cache do"
        lines << "    pages :all"
        lines << "  end"
        lines << ""
      end


      attrs.each do |attr_name, attr_config|
        if attr_config[:type].to_s == "linkable"
          lines << "  has_link :#{attr_name}"
        end
      end

      attrs.each do |attr_name, attr_config|
        if attr_config[:type].to_s == "image"
          lines << "  image :#{attr_name}"
        end
      end


      if is_resource
        resource_methods = [:get, :url, :year]

        if attrs[:release_date]
          resource_methods << :formatted_release_date
        end

        if resource_methods.try(:any?)
          lines << ""
          lines << "  define_resource_methods #{resource_methods.map{|m| ':' + m.to_s }.join(', ')}"
        end

        lines << "  def self.base_url(locale = I18n.locale)"
        lines << '    Cms.url_helpers.send("blog_#{locale}_path")'
        lines << '  end'
      end

      if attrs[:release_date]
        lines << "  before_save :init_release_date"
        lines << "  def init_release_date"
        lines << "    self.release_date = self.created_at if self.release_date.blank?"
        lines << "  end"
      end


      lines << "end"
      lines << ""

      lines_str = lines.join("\n")

      model_file_path = "app/models/#{@model_file_name}.rb"
      create_file model_file_path, lines_str
    end

    def create_model_migration
      migration_config = compute_model_config
      attrs = migration_config[:attributes]
      lines = []
      lines << "class #{@migration_class_name} < ActiveRecord::Migration#{migration_version}"
      lines << "  def change"
      lines << "    create_table :#{@table_name} do |t|"
      attrs.each do |attr_name, definition|
        column_type = definition[:ar_type] || definition[:type] || "string"
        lines << "      t.#{column_type} :#{attr_name}"
      end
      lines << "      t.timestamps null: false"

      lines << "    end"


      if migration_config[:translated_attribute_names].try(:any?)
        translated_attribute_names_str = migration_config[:translated_attribute_names].map{|attr| ":" + attr.to_s }.join(", ")
        lines << "    create_translation_table(#{@model_class_name}, #{translated_attribute_names_str})"
      end

      lines << "  end"
      lines << "end"
      lines << ''

      @migration_code = lines.join("\n")
      #migration_from_string migration_content, "db/migrate/#{@migration_file_name}.rb", migration_version: migration_version

      migration_template "migrations/create_model.rb.erb", "db/migrate/create_#{@table_name}.rb", migration_version: migration_version
    end



  end
end