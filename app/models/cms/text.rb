module Cms
  class Text < ActiveRecord::Base
    self.table_name = :texts
    attr_accessible *attribute_names
    globalize :content, translation_table_name: :text_translations

    has_cache do
      pages :all
    end

    def self.create_with_translations(key, translations = {})
      text = Text.new(key: key)
      if translations.present?
        translations.each do |locale, content|
          text.translations << text.translations.new(locale: locale, content: content)
        end
        text.save
      end
    end

    def self.load_translations(force = false)
      if !self.try(:table_exists?)
        return nil
      end
      if force || !self.class_variable_defined?(storage_variable_name)
        texts = self.all.joins(:translations).where(text_translations: {locale: I18n.locale}).pluck("key", "text_translations.content")
        self.class_variable_set(storage_variable_name, texts)
      end
    end

    def self.get_translations
      self.load_translations
      class_variable_get(storage_variable_name)
    end

    def self.storage_variable_name
      :"@@_texts_#{I18n.locale}"
    end

    def self.t(*args)
      if !self.try(:table_exists?)
        return nil
      end
      keys = args.take_while{|arg| arg.is_a?(String) || arg.is_a?(Symbol) }

      keys.each do |key|
        str = (self.get_translations.select{|t| t[0] == key.to_s }.first)
        if str.present? && str[1].present?
          s = str[1]
          interpolation_keys = s.scan(/\%\{[a-z_]{1,}[\d]{0,}[a-z_]{0,}\}/).map{|s| s[2, s.length - 3] }
          provided_hash = args.last.is_a?(Hash) ? args.last : nil
          if provided_hash.present?
            provided_valid_keys = provided_hash.keys.map(&:to_s).select{|k| interpolation_keys.include?(k) }
            provided_valid_keys.each do |k|
              v = provided_hash[k.to_sym].to_s
              s = s.gsub("%{#{k}}", v)
            end

            return s
          end

          return s
        end
      end


      nil
    end
  end
end