module Cms
  module Helpers
    module AnotherFormsHelper
      class << self
        attr_accessor :wrap_html_defaults

        def included(base)
          methods = [:input]
          if base.respond_to?(:helper_method)
            base.helper_method methods
          end
        end
      end

      def input(resource_name, input_name, options = {})
        resource = nil
        if !resource_name.is_a?(String) && !resource_name.is_a?(Symbol)
          resource = resource_name
          resource_name = resource_name.class.name.underscore
        end
        input_name = input_name.to_s
        defaults = {
            type: :string,
            required: false,
            tabindex: nil,
            use_required_mark: false,
            use_required_attribute: true
        }
        options = defaults.merge(options)
        options[:input_html] ||= {}

        options[:type] = :email if input_name == "email"
        options[:type] = :tel if input_name == "phone"

        i18n_resource_scope = options[:i18n_resource_scope] || resource_name

        html_name = options[:name] != false ? "#{resource_name}[#{input_name}]" : nil
        html_input_id = "#{resource_name}__#{input_name}"
        input_type = options[:type]
        input_type = :text if options[:type] == :string
        input_type = :text if options[:type] == :date

        wrap_html = {
            class: "input-field"
        }.merge(Cms::Helpers::AnotherFormsHelper.wrap_html_defaults || {})

        (options[:wrap_html] || {}).map{|k, v|
          default_value = wrap_html[k.to_sym];

          if k.to_sym == :class
            wrap_html[k.to_sym] += " #{v}"
          else
            wrap_html[k.to_sym] = v
          end
        }

        if options[:input_template].present?
          wrap_html[:class] += " #{options[:input_template]}-input-field"
        end

        wrap_html[:class] += " input-#{options[:type]}"

        attr_value = options[:value] || resource.try(input_name)
        attr_value = "" if options[:reset]
        input_content = ""




        i18n_key = options[:i18n_key].present? ? options[:i18n_key].to_s : input_name
        label_text = (I18n.t("forms.labels.#{i18n_resource_scope}.#{i18n_key}", raise: true) rescue nil) || (I18n.t("forms.labels.common.#{i18n_key}", raise: true) rescue nil) || I18n.t("forms.#{i18n_resource_scope}.#{i18n_key}", raise: true) rescue I18n.t("forms.#{i18n_key}", raise: true) rescue input_name.humanize
        label_text = i18n_key.humanize if label_text.blank?
        label_html_attributes = { for: html_input_id, class: "placeholder sub_title" }.merge(options[:reset_label_html] || {})
        input_placeholder_text = (I18n.t("forms.placeholders.common.#{input_name}", raise: true) rescue nil) || I18n.t("forms.placeholders.#{i18n_resource_scope}.#{input_name}", raise: true) rescue label_text
        input_html_attributes = {name: html_name, id: html_input_id, type: input_type, placeholder: input_placeholder_text }.merge(options[:input_html])
        html_input_id = input_html_attributes[:id]

        if options[:required]
          wrap_html[:class] += " required"

          if options[:use_required_attribute]
            input_html_attributes[:required] = "required"
          end

          if options[:use_required_mark]
            label_text = label_text + "<span class='required-mark'>*</span>"
          end
        end


        able_to_be_present = true

        if options[:type] == :text
          input_html_attributes.delete(:type)
          input_content = attr_value
        elsif options[:type] == :checkbox
          checkbox_value = options[:checkbox_value]
          input_html_attributes[:value] = checkbox_value
          if options[:checked]
            input_html_attributes[:checked] = "checked"
          else
            input_html_attributes[:checked] = attr_value.present?
          end
        elsif options[:type] == :date && !options[:multiple_date_inputs]
          date_format = options[:date_format] || :default
          if date_format.is_a?(Symbol)
            date_format = I18n.t("date.format_placeholders.#{date_format}")
          end
          input_html_attributes[:placeholder] = date_format
          input_html_attributes[:type] = "text"
          input_html_attributes[:value] = attr_value
        else
          input_html_attributes[:value] = attr_value
        end

        if options[:tabindex].present?
          input_html_attributes[:tabindex] = options[:tabindex]
        end


        value_present = attr_value.present?
        if options[:type] == :file
          value_present = attr_value.respond_to?(:exists?) && attr_value.exists?
          if attr_value.respond_to?(:exists?) && !attr_value.exists?
            input_html_attributes.delete(:value)
          end
        end


        if able_to_be_present && value_present
          input_html_attributes[:class] = (c = input_html_attributes[:class]).present? ? c + " used" : "used"
        end

        input_tip_title = I18n.t("forms.tooltips.#{i18n_resource_scope}.#{input_name}.title", raise: true) rescue nil
        input_tip_description = I18n.t("forms.tooltips.#{i18n_resource_scope}.#{input_name}.description", raise: true) rescue nil
        input_tip_description = input_tip_description.present? ? input_tip_description.html_safe : nil
        show_input_tip = input_tip_title.present? || input_tip_description.present?

        input_html_attributes_str = input_html_attributes.map{|k, v| "#{k}='#{v}'" }.join(' ')

        #puts "input type: #{options[:type].inspect}"



        if options[:type] == :text
          input_tag_str = "<textarea #{input_html_attributes_str}>#{input_content}</textarea>"
        elsif options[:type] == :file
          if attr_value.respond_to?(:exists?) && attr_value.exists?
            input_tag_str = "<div><a href='#{attr_value.url}'>#{attr_value.url.split("/").last.split("?").first}</a></div>"
          else
            input_tag_str = ""
          end

          input_tag_str = "<input #{input_html_attributes_str} />#{input_tag_str}"
        elsif options[:type] == :checkbox
          checkbox_label_text = options[:checkbox_label_text]
          input_tag_str = "<input #{input_html_attributes_str}/>"
          if checkbox_label_text.present?
            input_tag_str = input_tag_str + "<label for='#{html_input_id}'>#{checkbox_label_text}</label>"
          end
        elsif options[:type] == :select
          select_options = options[:select_options]
          selected = attr_value
          options_str = select_options.map{|o|
            o = [o] if !o.is_a?(Array);
            opt_name = o[1] || o[0];
            opt_value = o[0];
            selected_str = '';
            selected_str = " selected='selected'" if !selected.nil? && selected == opt_value
            #puts "selected: #{selected}"
            #puts "opt_value: #{opt_value}"
            "<option value='#{opt_value}'#{selected_str}>#{opt_name}</option>"
          }.join("")
          input_tag_str = "<select #{input_html_attributes_str}>#{options_str}</select>"
        elsif options[:type] == :radio_buttons
          radio_options = options[:radio_options]
          options_str = radio_options.map.with_index{|o, i|
            o = [o] if !o.is_a?(Array);
            opt_name = o[1] || o[0];
            opt_value = o[0];
            opt_selected = !selected.nil? && selected == opt_value
            opt_input_id = "#{html_input_id}__#{i}"
            if input_html_attributes[:name].present?
              html_name = input_html_attributes[:name]
            end
            opt_input_attrs = {type: "radio", value: opt_value, name: html_name, id: opt_input_id}
            if opt_selected
              opt_input_attrs[:checked] = "checked"
            end
            opt_input_str = content_tag(:input, "", opt_input_attrs)
            opt_label_str = content_tag(:label, opt_name, {class: "radio-label", for: opt_input_id})
            "<li>#{opt_input_str}#{opt_label_str}<div class='check'></div></li>"
          }.join("")
          input_tag_str = "<ul>#{options_str}</ul>"
        elsif options[:type] == :checkboxes
          checkbox_options = options[:checkbox_options]
          options_str = checkbox_options.map.with_index{|o, i|
            o = [o] if !o.is_a?(Array);
            opt_name = o[1] || o[0];
            opt_value = o[0];
            opt_selected = !selected.nil? && selected == opt_value
            opt_input_id = "#{html_input_id}__#{i}"
            opt_input_attrs = {type: "checkbox", value: opt_value, name: "#{html_name}[]", id: opt_input_id}
            if opt_selected
              opt_input_attrs[:checked] = "checked"
            end
            opt_input_str = content_tag(:input, "", opt_input_attrs)
            opt_label_str = content_tag(:label, opt_name, {class: "checkbox-label", for: opt_input_id})
            "<li>#{opt_input_str}#{opt_label_str}<div class='check'></div></li>"
          }.join("")
          input_tag_str = "<ul>#{options_str}</ul>"
        elsif options[:type] == :date && options[:multiple_date_inputs]
          attrs_for_inputs = [{placeholder: "MM", name: "#{html_name}[MM]"}, {placeholder: "DD", name: "#{html_name}[DD]"}, {placeholder: "YYYY", name: "#{html_name}[YYYY]"}]
          input_tag_str = attrs_for_inputs.map{|input_attrs| content_tag(:input, "", input_attrs) }.join("")
        else
          input_tag_str = "<input #{input_html_attributes_str} />"
        end

        if show_input_tip
          input_icon = "svg/question-mark.svg"
        else
          input_icon = ""
        end

        input_icon = options[:icon].present? ? options[:icon] : input_icon
        input_icon_class = "input-icon inside"
        input_icon_class = options[:icon_class].present? ? input_icon_class + " " + options[:icon_class] : input_icon_class

        if input_icon.present?
          input_icon_str = "<div class='#{input_icon_class}'>#{embedded_svg_from_assets(input_icon)}</div>"
        else
          input_icon_str = ""
        end

        input_tip_str = ""
        if show_input_tip
          input_tip_title_str = input_tip_title.present? ? "<div class='title_tip'>#{input_tip_title}</div>" : ""
          input_tip_description_str = input_tip_description.present? ? "<div class='text_box'>#{input_tip_description}</div>" : ""
          input_tip_str = "<div class='input-tip'><div class='svg_tringle'>#{embedded_svg_from_assets("svg/black-triangle.svg")}</div>#{input_tip_title_str}#{input_tip_description_str}</div>"
        end

        input_help = I18n.t("forms.help.#{i18n_resource_scope}.#{input_name}", raise: true) rescue nil
        input_help_str = input_help.present? ? "<div class='sub_sub_title'>#{input_help}</div>" : ""


        label_html_attributes_str = label_html_attributes.map{|k, v| "#{k}='#{v}'" }.join(' ')

        wrap_html_attributes_str = wrap_html.map{|k, v| "#{k}='#{v}'" }.join(' ')


        label_str = options[:label] != false ? "<label #{label_html_attributes_str}>#{label_text}</label>" : ""
        input_template_args = [wrap_html_attributes_str, label_str, input_tag_str, input_icon_str, input_tip_str, input_help_str]
        input_template_method = options[:input_template]

        if input_template_method.present?
          input_template_method = "#{input_template_method}_input_template"
        else
          input_template_method = "input_template"
        end

        send input_template_method, *input_template_args
      end

      def input_template(wrap_html_attributes_str, label_str, input_tag_str, input_icon_str, input_tip_str, input_help_str)
        "<div #{wrap_html_attributes_str}>#{label_str}#{input_tag_str}#{input_icon_str}#{input_tip_str}</div>#{input_help_str}".html_safe
      end

      def profile_input_template(wrap_html_attributes_str, label_str, input_tag_str, input_icon_str, input_tip_str, input_help_str)
        "<div #{wrap_html_attributes_str}>#{label_str}<div class='profile-input-content'>#{input_tag_str}#{input_icon_str}#{input_tip_str}</div>#{input_help_str}</div>".html_safe
      end

      def select_input(resource_name, input_name, select_options, selected = nil)

      end
    end
  end
end