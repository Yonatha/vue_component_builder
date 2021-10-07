require "vue_component_builder/version"
require 'rails/generators/base'
require 'fileutils'

module VueComponentBuilder
  module Generators
    class NewGenerator < Rails::Generators::Base

      def execute
        p 'Building Vue component...'

        if ARGV.empty?
          raise StandardError, <<-ERROR.strip_heredoc

          Be sure to have informed the params needed:
            e.g
              model=Fruit
              component=MyFruitComponent
              theme=element-plus
              exclude=id,created_at,updated_at [optional]

            rails g vue_component_builder:new model=Fruit  component=MyFruitComponent theme=element-plus exclude=id,created_at,updated_at
          ERROR
        end

        input = {}
        ARGV.to_a.each do |arg|
          command = arg.split('=')
          input[command[0].to_sym] = command[1]
        end

        input[:exclude] = input[:exclude].try(:split, ',')

        if !input[:theme].present? || !input[:component].present? || !input[:model].present?
          raise StandardError, <<-ERROR.strip_heredoc

          Be sure to have informed the params needed:
            e.g
              model=Fruit
              component=MyFruitComponent
              theme=element-plus
              exclude=id,created_at,updated_at [optional]

            rails g vue_component_builder:new model=Fruit  component=MyFruitComponent theme=element-plus exclude=id,created_at,updated_at
          ERROR
        end

        @options = {
          component: input[:component],
          theme: input[:theme],
          model: {
            name: input[:model].downcase.to_s,
            attributes: [],
            exclude: input[:exclude],
            class: eval(input[:model].capitalize.to_s)
          },
          controller: {
            name: "#{input[:model].to_s.pluralize}Controller",
            methods: []
          },
        }

        @options[:controller].merge!(methods: eval("Api::V1::#{@options[:controller][:name]}").instance_methods(false).map { |m| m.to_s })
        attributes = @options[:model][:class].columns_hash.map do |k, v|
          label = I18n.t("activerecord.attributes.#{@options[:model][:name]}.#{k}", default: k.upcase)
          unless @options[:model][:exclude].nil?
            { name: k, type: v.type.to_s, label: label } if !@options[:model][:exclude].include? k
          else
            { name: k, type: v.type.to_s, label: label }
          end
        end
        @options[:model].merge!(attributes: attributes.compact)
        self.build
      end

      protected

      def build
        output_dir = "#{Rails.root}/public/#{@options[:component].to_s}.vue"
        @form_attributes = generate_form_attribute

        # Read tempalte
        @data_hook = data_hook
        @mounted_hook = mounted_hook
        @methods_hook = methods_hook
        @table = generate_table
        @script = readTemplate('script.js.erb')
        template = readTemplate('main.vue.erb')

        # Output
        File.open(output_dir, 'w') { |file| file.write(template) }
        p "The component 'public/#{@options[:component].to_s}.vue' was builded successfully"
      end

      def generate_form_attribute
        response = ''
        @options[:model][:attributes].each do |attribute|
          inputTemplate = case attribute[:type]
                          when 'integer'
                            'integer'
                          when 'string'
                            'string'
                          when 'boolean'
                            'boolean'
                          when 'datetime'
                          when 'date'
                            'datetime'
                          else
                            'string'
                          end

          @attribute = attribute
          response += readTemplate("/form/#{inputTemplate}.vue.erb")
        end
        response
      end

      def generate_validateForm
        presence_validated_attributes = @options[:model][:class].validators.map do |validator|
          validator.attributes if validator.is_a?(ActiveRecord::Validations::PresenceValidator)
        end.compact.flatten

        @rules = ""
        presence_validated_attributes.each do |attribute|
          @attribute = @options[:model][:attributes].select { |attr| attr[:name] == attribute.to_s }[0]
          @rules += readTemplate("js/methods/validate_rules.js.erb")
        end
        @rules
        readTemplate("js/methods/validate.js.erb")
      end

      def generate_reset_form
        @attributes = ""
        @options[:model][:attributes].each do |attribute|
          @attributes += "#{attribute[:name]}: #{attribute[:type] == 'boolean' ? 'false' : 'null'},"
        end
        readTemplate("js/methods/resetForm.js.erb")
      end

      def readTemplate templateName
        template_dir = "#{__dir__}/builder/template/#{@options[:theme]}"
        template = ERB.new File.read("#{template_dir}/#{templateName}"), nil, '%'
        template.result(binding)
      end

      def data_hook
        attributes = ''
        @options[:model][:attributes].each do |attribute|
          unless attribute[:name] == 'id'
            @attribute = attribute
            inputTemplate = case attribute[:type]
                            when 'integer'
                              'integer'
                            when 'string'
                              'string'
                            when 'boolean'
                              'boolean'
                            when 'datetime'
                            when 'date'
                              'datetime'
                            else
                              'string'
                            end

            attributes += readTemplate("js/#{inputTemplate}.js.erb")
            attributes += ",\n"
          end
        end
        @attributes = attributes.chop
        response = readTemplate('js/hooks/data.js.erb')
        response
      end

      def mounted_hook
        readTemplate('js/hooks/mounted.js.erb')
      end

      def methods_hook
        @methods = ""
        @options[:controller][:methods].each do |method|
          method_name = method.to_s
          @method_name = method_name
          @methods += eval("generate_call_#{method_name}")
        end

        @validateForm = generate_validateForm
        @resetForm = generate_reset_form

        response = readTemplate('js/hooks/methods.js.erb')
        response
      end

      def generate_call_index
        readTemplate('js/methods/index.js.erb')
      end

      def generate_call_show
        readTemplate('js/methods/show.js.erb')
      end

      def generate_call_create
        readTemplate('js/methods/create.js.erb')
      end

      def generate_call_destroy
        readTemplate('js/methods/destroy.js.erb')
      end

      def generate_call_update
        readTemplate('js/methods/update.js.erb')
      end

      def generate_call_edit
        ""
      end

      def generate_table
        @columns = generate_table_column
        readTemplate('/table/table-component.vue.erb')
      end

      def generate_table_column
        content = ""
        @options[:model][:attributes].each do |attribute|
          content += generate_column_by_type attribute
        end
        content
      end

      def generate_column_by_type attribute
        @attribute = attribute
        case attribute[:type]
        when 'boolean'
          readTemplate('/table/boolean.vue.erb')
        else
          readTemplate('/table/string.vue.erb')
        end
      end
    end
  end
end
