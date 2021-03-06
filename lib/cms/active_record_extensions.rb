
module Cms
  module ActiveRecordExtensions
    extend ActiveSupport::Concern

    def boolean_changed?(attr)
      if !(attr.is_a?(String) || attr.is_a?(Symbol))
        raise ArgumentError, "boolean_changed?: argument must be String or Symbol; provided argument: #{attr.inspect}"
      end
      was = send("#{attr}_was") || false
      v = send(attr)

      v != was
    end

    module ClassMethods

      # def human_attribute_name()
      #
      # end

      def has_seo_tags
        has_one :seo_tags, class_name: "Cms::MetaTags", as: :page, autosave: true
        accepts_nested_attributes_for :seo_tags
        attr_accessible :seo_tags, :seo_tags_attributes
      end

      def has_page_alias(perform_build_if_not_exist = false)
        has_one :page_alias, as: :page, class_name: "Cms::PageAlias", autosave: true
        accepts_nested_attributes_for :page_alias
        attr_accessible :page_alias, :page_alias_attributes
        Cms::PageAlias.register_resource_class(self)
        if perform_build_if_not_exist
          before_save do
            build_page_alias if !page_alias && (!respond_to?(:published?) || published?)
          end
        end
      end

      # def has_sitemap_record
      #   has_one :sitemap_record, as: :sitemap_resource
      #   attr_accessible :sitemap_record
      # end




      def has_sitemap_record(options = {}, &block)
        defaults = {class: Cms.config.sitemap_element_class}
        options = defaults.merge(options)
        class_name = options[:class].is_a?(Class) ? options[:class].name : options[:class]
        has_one :sitemap_record, class_name: class_name, as: :page
        accepts_nested_attributes_for :sitemap_record
        attr_accessible :sitemap_record, :sitemap_record_attributes
        Cms::SitemapElement.register_resource_class(self)
        safe_include(self, Cms::Sitemap::InstanceMethods)
        self.class_variable_set(:@@_sitemap_record_method, block)
      end

      def reload_routes
        DynamicRouter.reload
      end

      def image(name, *args)
        options = args.extract_options!
        if options[:styles].blank? && Cms.config.default_image_styles_enabled
          options[:styles] = Cms.config.default_image_styles
        end

        if options[:styles].present? && options[:styles].is_a?(String)
          options[:styles] = { default: options[:styles] }
        end

        has_attached_file name, *args, options
        attr_accessible name
        allow_delete_attachment name
        do_not_validate_attachment_file_type name if respond_to?(:do_not_validate_attachment_file_type)
        validates_attachment_content_type name, :content_type => /\Aimage/
      end

      def pdf(name = "pdf", *args)
        has_attached_file name, *args
        do_not_validate_attachment_file_type name if respond_to?(:do_not_validate_attachment_file_type)
        attr_accessible name
        allow_delete_attachment name
      end

      def allow_delete_attachment(*names)
        names.each do |k|
          attr_accessor "delete_#{k}".to_sym
          attr_accessible "delete_#{k}".to_sym

          before_validation { send(k).clear if send("delete_#{k}") == '1' }
        end
      end

      def reprocess_attachments
        if respond_to?(:attachment_definitions)
          names = attachment_definitions.keys
          if names.any?
            all.each do |item|
              names.each do |name|
                attachment = item.send(name)
                attachment.reprocess! if attachment.exists?
              end
            end
          end
        end
      end

      def images_count
        count = 0
        definitions = attachment_definitions
        if definitions.any?
          all.each do |item|
            definitions.each do |name, definition|
              if definition && definition[:styles].present?
                attachment = item.send(name)
                keys = definition[:styles].keys.select{|k| k != :original }
                if keys.any? && attachment.exists?
                  count += keys.count
                end
              end
            end
          end
        end
      end



      def has_html_block(*names, **options)
        names = [:content] if names.empty?
        options[:class] ||= "Cms::HtmlBlock"
        class_name = options[:class]
        if !class_name.is_a?(String)
          class_name = options[:class].name
        end



        reflection_name = class_name.split("::").last.underscore.pluralize.to_sym
        if self._reflections[class_name].nil?
          has_many reflection_name, class_name: class_name, as: :attachable
        end
        names.each do |name|
          name = name.to_sym

          if !has_html_block_field_name?(name)
            store_html_field_name(name)
            options[:getter] = true if options[:getter].nil?
            options[:setter] = true if options[:setter].nil?
            define_getter = options[:getter]
            define_setter = options[:setter]

            has_one name, -> { where(attachable_field_name: name) }, class_name: class_name, as: :attachable, autosave: true
            accepts_nested_attributes_for name
            attr_accessible name, "#{name}_attributes".to_sym


            if define_getter

              self.send :define_method, "#{name}" do |locale = I18n.locale|
                owner = self.association(name).owner
                owner_class = owner.class
                puts "owner_class: #{owner_class.name}"
                puts "owner_id: #{owner.id}"
                puts "owner_field_name: #{name}"
                HtmlBlock.all.where(attachable_type: owner_class.name, attachable_id: owner.id, attachable_field_name: name).first.try(&:content)
              end
            end

            if define_setter
              self.send :define_method, "#{name}=" do |value|
                owner = self.association(name).owner
                owner_class = owner.class
                html_block = HtmlBlock.all.where(attachable_type: owner_class.name, attachable_id: owner.id, attachable_field_name: name).first_or_initialize
                html_block.content = value
                html_block.save
              end
            end


          end
        end
      end

      def has_content_blocks(name = nil, **options)

        multiple = options[:multiple]
        options[:class_name] ||= options[:class] || Cms.config.content_block_class


        multiple = true if multiple.nil?

        reflection_method = :has_one
        reflection_method = :has_many if multiple

        name ||=  multiple ? :content_blocks : :content_block

        return false if self._reflections.keys.include?(name.to_s)

        send reflection_method, name, -> { where(attachable_field_name: name) }, as: :attachable, class_name: options[:class_name], dependent: :destroy, autosave: true

        if !has_content_block_field_name?(name)
          store_content_field_name(name)

          accepts_nested_attributes_for name
          attr_accessible name, "#{name}_attributes".to_sym

          define_method "#{name}_changed?" do
            true
          end
        end
      end

      def has_content_block(name = nil, **options)
        options[:multiple] = false
        has_content_blocks(name, options)

        return options
      end



      def has_tags(name = :tags, multiple = true)
        association_method = multiple ? :has_many : :has_one

        association_name = multiple ? name.to_s.pluralize : name.to_s.singularize
        association_name_sym = association_name.to_sym
        if !self._reflections.keys.include?(:taggings)
          has_many :taggings, as: :taggable, class_name: 'Cms::Tagging', dependent: :destroy, autosave: true
        end

        associated_taggings_rel_name = :"#{association_name}_tagging#{'s' if multiple}"

        send association_method, associated_taggings_rel_name, -> { where(taggable_field_name: name) }, as: :taggable, class_name: 'Cms::Tagging', dependent: :destroy, autosave: true

        send association_method, association_name_sym, through: associated_taggings_rel_name, source: :tag, class_name: 'Cms::Tag'
        ids_field_name = multiple ? name.to_s.singularize + "_ids" : association_name + "_id"
        attr_accessible association_name, ids_field_name

        resource_class = self
        resource_name = self.name.underscore.gsub('/', '_')

        resource_ids_field_name = resource_name.singularize + "_ids"

        associations = Cms::Tag.taggable_associations
        if !associations.map(&:to_s).include?(association_name)
          associations << association_name_sym
          Cms::Tag.class_variable_set(:@@taggable_associations, associations)
        end

        Cms::Tag.class_eval do
          has_many resource_name.pluralize.to_sym, through: :taggings, source: :taggable, class_name: resource_class.name, source_type: resource_class
          attr_accessible resource_ids_field_name
        end

      end

      def has_tag(name = :tag)
        has_tags(name, false)
      end

      def store_field_name(array_name, name)
        if self.class_variable_defined?(array_name)
          html_field_names = self.class_variable_get(:@@html_field_names)
        end
        html_field_names ||= []

        html_field_names << name.to_s
        class_variable_set(:@@html_field_names, html_field_names)
      end

      def define_obj

      end

      def has_obj?(name)

      end

      def html_block_field_names
        return [] if !class_variable_defined?(:@@html_field_names)
        class_variable_get(:@@html_field_names) || []
      end

      def has_html_block_field_name?(name)
        has_block_field_name?(:@@html_field_names, name)
      end

      def store_html_field_name(name)
        store_field_name(:@@html_field_names, name)
      end

      def has_content_block_field_name?(name)
        has_block_field_name?(:@@content_field_names, name)
      end

      def has_block_field_name?(var_name, name)
        self.class_variable_defined?(:"#{var_name}") && (names = self.class_variable_get(:"#{var_name}")).present? && names.include?(name.to_s)
      end

      def store_content_field_name(name)
        store_field_name(:@@content_field_names, name)
      end

      def line_separated_fields(*names, **options)
        safe_include(self, Cms::TextFields)

        names.each do |name|
          define_method name do |parse = true|
            line_separated_field(name, parse, options)
          end

          define_method "#{name}=" do |val|
            send(:line_separated_field=, name, val, options)
          end
        end
      end

      def price_fields(*names)
        safe_include(self, Cms::Pricing)
        safe_extend(self, Enumerize)
        names.each do |name|
          enumerize :"#{name}_currency", in: [:usd, :uah, :eur], default: :usd
          define_method name do |currency = nil|
            price_for(name, currency)
          end

          define_method name do |currency = nil|
            price_for(name, currency)
          end
        end
      end

      def line_separated_field(*names, **options)
        line_separated_fields(*names, options)
      end

      def properties_fields(*names)
        safe_include(self, Cms::TextFields)
        opts = names.extract_options!
        opts = {keep_empty_values: false}.merge(opts)

        names.each do |name|
          define_method name do |locale = I18n.locale|
            properties_field(name, locale, opts[:keep_empty_values])
          end
        end
      end

      def properties_field(*names)
        properties_fields(*names)
      end

      def has_link(name = :linkable, optional: true)
        name = name.to_sym if name.is_a?(String)

        association_options = { polymorphic: true }
        if Rails::VERSION::MAJOR >= 5
          association_options[:optional] = optional
        else
          association_options[:required] = !optional
        end

        belongs_to name, association_options
        attr_accessible name

        define_method "#{name}=" do |value|
          if value.blank?
            association(name).writer(nil)
          elsif value.is_a?(String)
            parts = value.split("#")
            return if parts.blank?
            page_class = parts[0].constantize
            page_id = parts[1].to_i
            page = page_class.find(page_id)
            association(name).writer(page)
          elsif value.is_a?(ActiveRecord)
            association(name).writer(value)
          end
        end
      end

      def boolean_scope(column_name, positive_name = nil, negative_name = nil)
        if positive_name == false && negative_name == false
          return
        end
        positive_name = column_name if positive_name.nil? || positive_name == true
        negative_name = "un#{column_name}" if negative_name.nil? || negative_name == true

        positive_value = 't'
        negative_value = 'f'
        if defined?(ActiveRecord::ConnectionAdapters::Mysql2Adapter) && ActiveRecord::Base.connection.is_a?(ActiveRecord::ConnectionAdapters::Mysql2Adapter)
          positive_value = true
          negative_value = false
        end

        if positive_name
          scope positive_name, -> { where(:"#{column_name}" => positive_value) }
        end

        if negative_name
          scope negative_name, -> { where("#{column_name} = ? OR #{column_name} IS NULL", negative_value) }
        end
      end

      def range_scope(column_name, scope_name = nil)
        scope_name ||= "with_#{column_name}_between".to_sym

        scope scope_name, lambda { |h_or_string_or_from = nil, to = nil|
          if h_or_string_or_from.nil? && to.nil?
            return current_scope
          end

          to_numeric_method = :to_f # #to_i or #to_f

          if h_or_string_or_from.is_a?(Hash)
            price_from = h_or_string_or_from[:from].try(to_numeric_method)
            price_to = h_or_string_or_from[:to].try(to_numeric_method)
          elsif to
            price_from = h_or_string_or_from.try(to_numeric_method)
            price_to = to.try(to_numeric_method)
          elsif h_or_string_or_from.is_a?(String)
            price_from, price_to = h_or_string_or_from.split(/[\,\-]/).map{|e| next nil if e.blank?; next e.try(to_numeric_method) }
          else
            price_from = h_or_string_or_from.try(to_numeric_method)
            price_to = to.try(to_numeric_method)
          end

          price_from = nil if price_from.blank? || price_from == 0
          price_to = nil if price_to.blank? || price_to == 0

          if price_from.blank? && price_to.blank?
            return current_scope
          end

          has_upper_limit = price_to.present? && price_to != 0
          has_lower_limit = price_from.present? && price_from != 0

          if price_from.blank?
            price_from = 0
          end

          a = price_from
          b = price_to || 0

          if has_upper_limit && has_lower_limit
            params = [a, b]
          elsif has_lower_limit
            params = [a]
          else
            params = [b]
          end

          current_scope.where("#{"#{column_name} >= ?" if has_lower_limit} #{' AND ' if has_lower_limit && has_upper_limit} #{"#{column_name} <= ?" if has_upper_limit}", *params)
        }
      end

      def string_scope(column_name, scope_name = nil)
        if scope_name.blank?
          scope_name = "with_#{column_name}"
        end


        #scope sc, -> { where(:"#{column_name}" =>  ) }

      end

      def enumerize_multiple_scope(column_name, scope_name = nil, default_condition = :or)
        if scope_name.blank?
          scope_name = "with_#{column_name}"
        end

        if !default_condition.is_a?(Symbol)
          default_condition = default_condition.to_sym
        end

        if default_condition != :or && default_condition != :and
          default_condition = :or
        end

        scope scope_name.to_sym, ->(query_values, condition = default_condition) do
          if !query_values.is_a?(Array)
            query_values = [query_values]
          end
          ids = current_scope.pluck(:id, column_name).select{|item|
            record_values = JSON.parse(item[1]) rescue []
            if record_values.blank?
              next false
            end
            if condition == :or
              query_values.any?{|v| v.in?(record_values) }
            elsif :and
              valid = true
              query_values.map{|v|
                if !v.in?(record_values)
                  valid = false
                  break
                end
              }
              next valid
            else
              false
            end
          }.map(&:first)

          current_scope.model.where(id: ids)
        end

      end

      def nested_attributes_for(key)
        define_method :"#{key}_attributes=" do |params|
          return if params.nil?

          params_count = params.count
          params_max_index = params_count - 1
          self.send(key).each_with_index do |c, i|
            c.delete if i > params_max_index
          end



          params.each_with_index do |entry_params, entry_index|
            entry_params = entry_params[1] if entry_params.is_a?(Array)
            entry_index = entry_index.to_i
            entry = self.send(key)[entry_index]
            entry ||= self.send(key).new
            #puts "personal_helper_params: #{personal_helper_params.inspect}"
            entry.update(entry_params)
          end
        end
      end

      def enumerize_multiple(name, values)
        define_method :"#{name}=" do |value|
          str = value
          if value.is_a?(Array)
            str = "[#{value.select{|item| item.to_s.in?(values.map(&:to_s))  }.map{|s| "\"#{s}\"" }.join(",")}]"
          end

          self["#{name}"] = str
        end

        define_method :"#{name}" do
          str = self["#{name}"]
          return [] if str.blank? || str == "[]"
          str[1, str.length - 2].split(",").map{|s| s[1, s.length - 2] }
        end
      end

      def define_resource_methods(*method_names)




        method_definitions = {
          get: ->{
            define_singleton_method :get do |url_fragment, base_relation = self|
              if base_relation.respond_to?(:published)
                base_relation = base_relation.published
              end
              if base_relation.try(:translates?)
                base_relation.joins(:translations).where(:"#{self.translation_class.table_name}" => { url_fragment: url_fragment, locale: I18n.locale }).first
              else
                base_relation.where(url_fragment: url_fragment).first
              end

            end
          },

          base_url: ->{
            define_singleton_method :base_url do |locale = I18n.locale|
              Cms.url_helpers.send("promotions_#{locale}_path")
            end
          },

          url: ->{
            define_method :url do |locale = I18n.locale|
              url_fragment = self.translations_by_locale[locale].try(:url_fragment)

              url_fragment.present? ? self.class.base_url(locale) + "/" + url_fragment : nil
            end
          },
          formatted_release_date: ->{
            define_method :formatted_release_date do |format = nil, value = nil|
              format ||= :short
              d = value.nil? ? try(:release_date) : value
              return nil if d.nil?
              if format == :short
                d.strftime("%d.%m.%Y")
              elsif format == :long
                month_name = I18n.t("genitive_month_names")[d.month - 1]
                "#{d.day} #{month_name} #{d.year}"
              end
            end
          },
          year: ->{
            define_method :year do
              release_date.try{|d| d.year }
            end
          }
        }

        available_methods = method_definitions.keys.map(&:to_s)

        if method_names.blank? || method_names.first == :all
          method_names = available_methods
        else
          method_names = method_names.select{|m|
            available_methods.include?(m.to_s)
          }
        end

        method_names.each do |m|
          method_definitions[m.to_sym].call
        end
      end

    end
  end



  def self.drop_content_blocks_table
    connection.drop_table :content_blocks

    if Cms::ContentBlock.include_translations?
      Cms::GlobalizeExtension.drop_translation_table!(Cms::ContentBlock)
    end
  end

  def self.create_html_blocks_table
    connection.create_table :html_blocks do |t|
      t.string :type
      t.text :content

      t.integer :attachable_id
      t.string :attachable_type
      t.string :attachable_field_name
      t.string :key

    end

    if Cms::HtmlBlock.include_translations?
      #Cms::HtmlBlock.initialize_globalize
      Cms::HtmlBlock.create_translation_table(:content)
    end
  end

  def self.create_texts_table
    connection.create_table :texts do |t|
      t.string :key, null: false
      t.text :content

      t.timestamps null: false
    end

    connection.add_index :texts, :key, unique: true

    if Cms::Config.use_translations
      Cms::Text.create_translation_table(:content)
    end
  end

  def self.drop_texts_table
    if Cms::Config.use_translations
     Cms::GlobalizeExtension.drop_translation_table!(Cms::Text)
    end

    #connection.remove_index :texts, :key, unique: true
    connection.remove_index :texts, :key

    connection.drop_table :texts

  end

  def self.drop_html_blocks_table
    connection.drop_table :html_blocks

    if Cms::HtmlBlock.include_translations?
      Cms::GlobalizeExtension.drop_translation_table!(Cms::HtmlBlock)
    end
  end

  def self.create_seo_tags_table
    connection.create_table :seo_tags do |t|
      t.string :page_type
      t.integer :page_id
      t.string :title
      t.text :keywords
      t.text :description
    end

    if Cms::MetaTags.include_translations?
      #Cms::MetaTags.initialize_globalize
      Cms::MetaTags.create_translation_table(:title, :keywords, :description)
    end
  end

  def self.create_sitemap_elements_table
    connection.create_table :sitemap_elements do |t|
      t.string :page_type
      t.integer :page_id

      t.boolean :display_on_sitemap
      t.string :changefreq
      t.float :priority

      t.timestamps null: false
    end
  end

  def self.drop_sitemap_elements_table
    connection.drop_table :sitemap_elements
  end

  def self.drop_seo_tags_table
    if Cms::MetaTags.include_translations?
      Cms::GlobalizeExtension.drop_translation_table!(Cms::MetaTags)
    end

    connection.drop_table :seo_tags
  end

  def self.create_pages_table
    connection.create_table Cms::Page.table_name do |t|
      t.string :type
      t.integer :sorting_position
      t.string :name
      t.text :content
      t.string :url
      t.string :h1_text

      t.timestamps null: false
    end

    if Cms::Page.include_translations?
      #Cms::Page.initialize_globalize
      #puts "translated: #{Cms::Page.translated_attribute_names}"
      Cms::Page.create_translation_table(:url, :content, :name, :h1_text )
    end
  end

  def self.create_page_aliases_table
    connection.create_table Cms::PageAlias.table_name do |t|
      t.boolean :disabled
      t.string :redirect_mode
      t.linkable :page
      t.text :urls

      t.timestamps null: false
    end

    if Cms::PageAlias.include_translations?
      #Cms::Page.initialize_globalize
      #puts "translated: #{Cms::Page.translated_attribute_names}"
      Cms::PageAlias.create_translation_table(:urls)
    end
  end


  def self.create_banner_table(options = {})
    ActiveRecord::Base.create_banner_table(options)
  end



  def self.drop_pages_table
    if Cms.config.use_translations
      Cms::GlobalizeExtension.drop_translation_table!(Cms::Page)
    end

    connection.drop_table :pages
  end

  def self.drop_page_aliases_table
    if Cms.config.use_translations
      Cms::GlobalizeExtension.drop_translation_table!(Cms::PageAlias)
    end

    connection.drop_table :page_aliases
  end


  def self.create_form_configs_table
    connection.create_table Cms::FormConfig.table_name do |t|
      t.string :type
      t.text :email_receivers

      t.timestamps null: false
    end
  end

  def self.drop_form_configs_table
    connection.drop_table :form_configs
  end

  def self.create_tags_table(options = {})
    return if Cms::Tag.table_exists?

    connection.create_table Cms::Tag.table_name do |t|
      t.integer :tagging_id
      t.string :name
      t.string :url_fragment
    end

    #Cms::Tag.initialize_globalize
    if Cms::Config.use_translations && respond_to?(:translates?)
      Cms::Tag.create_translation_table(:name, :url_fragment)
    end
  end

  def self.create_taggings_table
    return if Cms::Tagging.table_exists?
    connection.create_table Cms::Tagging.table_name do |t|
      t.integer :taggable_id
      t.string :taggable_type
      t.string :taggable_field_name
      t.integer :tag_id
    end
  end

  def self.create_exchange_rates_table
    return if Cms::ExchangeRate.table_exists?
    connection.create_table Cms::ExchangeRate.table_name do |t|
      t.string :provider
      t.text :json_data

      t.timestamps null: false
    end
  end

  def self.create_weather_data_table
    return if Cms::WeatherData.table_exists?
    connection.create_table Cms::WeatherData.table_name do |t|
      t.string :provider
      t.text :json_data
      t.string :locale

      t.timestamps null: false
    end
  end

  def self.drop_weather_data_table
    return if !Cms::WeatherData.table_exists?
    connection.drop_table Cms::WeatherData.table_name
  end

  def self.drop_exchange_rates_table
    return if !Cms::ExchangeRate.table_exists?
    connection.drop_table Cms::ExchangeRate.table_name
  end

  def self.drop_tags_table
    Cms::GlobalizeExtension.drop_translation_table!(Cms::Tag)

    connection.drop_table Cms::Tag.table_name


  end

  def self.drop_taggings_table
    connection.drop_table Cms::Tagging.table_name
  end


  def self.connection
    ActiveRecord::Base.connection
  end


  def self.normalize_tables(options = {})

    default_tables = [:form_configs, :pages, :page_aliases, :seo_tags, :html_blocks, :sitemap_elements, :texts ]
    tables = []
    if options[:only]
      if !options[:only].is_a?(Array)
        options[:only] = [options[:only]]
      end
      tables = options[:only].select{|t| t.to_s.in?(default_tables.map(&:to_s)) }
    elsif options[:except]
      if !options[:except].is_a?(Array)
        options[:except] = [options[:except]]
      end
      tables = default_tables.select{|t| !t.to_s.in?(options[:except].map(&:to_s)) }
    else
      tables = default_tables
    end

    tables
  end

  def self.create_tables(options = {})
    tables = normalize_tables(options)

    if tables.any?
      tables.each do |t|
        puts "create table: #{t}"
        send("create_#{t}_table")
      end
    end
  end

  def self.drop_tables(options = {})
    tables = normalize_tables(options)

    if tables.any?
      tables.each do |t|
        try(:"drop_#{t}_table") rescue next
      end
    end
  end
end

ActiveRecord::Base.send(:include, Cms::ActiveRecordExtensions)