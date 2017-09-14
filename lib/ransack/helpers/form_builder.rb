require 'action_view'

# Disable monkey-patch (breaks on Rails 5.2)
#
# | ActionView::Template::Error (wrong number of arguments (given 0, expected 1)):
# |      5:   <%= active_admin_form_for(resource, as: resource_name, url: send(:"#{scope}_session_path"), html: { id: "session_new" }) do |f|
# |      6:     f.inputs do
# |      7:       resource.class.authentication_keys.each_with_index { |key, index|
# |      8:         f.input key, label: t("active_admin.devise.#{key}.title"), input_html: { autofocus: index.zero? }
# |      9:       }
# |     10:       f.input :password, label: t('active_admin.devise.password.title')
# |     11:       f.input :remember_me, label: t('active_admin.devise.login.remember_me'), as: :boolean if devise_mapping.rememberable?
# |
# | ransack-c869fc210500/lib/ransack/helpers/form_builder.rb:9:in `value'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/tags/base.rb:53:in `value_before_type_cast'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/tags/text_field.rb:15:in `block in render'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/tags/text_field.rb:15:in `fetch'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/tags/text_field.rb:15:in `render'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/form_helper.rb:1520:in `email_field'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/form_helper.rb:1698:in `email_field'
# | formtastic (3.1.5) lib/formtastic/inputs/email_input.rb:36:in `block in to_html'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/capture_helper.rb:41:in `block in capture'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/capture_helper.rb:205:in `with_output_buffer'
# | rails-cffa32f95d29/actionview/lib/action_view/helpers/capture_helper.rb:41:in `capture'
# | formtastic (3.1.5) lib/formtastic/inputs/base/wrapping.rb:11:in `input_wrapping'
# | activeadmin (1.1.0) lib/active_admin/form_builder.rb:6:in `input_wrapping'
# | formtastic (3.1.5) lib/formtastic/inputs/email_input.rb:34:in `to_html'
# | formtastic (3.1.5) lib/formtastic/helpers/input_helper.rb:242:in `input'
# | arbre (1.1.1) lib/arbre/rails/forms.rb:30:in `proxy_call_to_form'
# | activeadmin (1.1.0) lib/active_admin/views/components/active_admin_form.rb:65:in `input'
#
#module ActionView::Helpers::Tags
#  # TODO: Find a better way to solve this issue!
#  # This patch is needed since this Rails commit:
#  # https://github.com/rails/rails/commit/c1a118a
#  class Base
#    private
#    def value(object)
#      object.send @method_name if object # use send instead of public_send
#    end
#  end
#end

RANSACK_FORM_BUILDER = 'RANSACK_FORM_BUILDER'.freeze

require 'simple_form' if
  (ENV[RANSACK_FORM_BUILDER] || ''.freeze).match('SimpleForm'.freeze)

module Ransack
  module Helpers
    class FormBuilder < (ENV[RANSACK_FORM_BUILDER].try(:constantize) ||
      ActionView::Helpers::FormBuilder)

      def label(method, *args, &block)
        options = args.extract_options!
        text = args.first
        i18n = options[:i18n] || {}
        text ||= object.translate(
          method, i18n.reverse_merge(:include_associations => true)
          ) if object.respond_to? :translate
        super(method, text, options, &block)
      end

      def submit(value = nil, options = {})
        value, options = nil, value if value.is_a?(Hash)
        value ||= Translate.word(:search).titleize
        super(value, options)
      end

      def attribute_select(options = nil, html_options = nil, action = nil)
        options = options || {}
        html_options = html_options || {}
        action = action || Constants::SEARCH
        default = options.delete(:default)
        raise ArgumentError, formbuilder_error_message(
          "#{action}_select") unless object.respond_to?(:context)
        options[:include_blank] = true unless options.has_key?(:include_blank)
        bases = [''.freeze].freeze + association_array(options[:associations])
        if bases.size > 1
          collection = attribute_collection_for_bases(action, bases)
          object.name ||= default if can_use_default?(
            default, :name, mapped_values(collection.flatten(2))
            )
          template_grouped_collection_select(collection, options, html_options)
        else
          collection = collection_for_base(action, bases.first)
          object.name ||= default if can_use_default?(
            default, :name, mapped_values(collection)
            )
          template_collection_select(:name, collection, options, html_options)
        end
      end

      def sort_direction_select(options = {}, html_options = {})
        unless object.respond_to?(:context)
          raise ArgumentError,
          formbuilder_error_message('sort_direction'.freeze)
        end
        template_collection_select(:dir, sort_array, options, html_options)
      end

      def sort_select(options = {}, html_options = {})
        attribute_select(options, html_options, 'sort'.freeze) +
        sort_direction_select(options, html_options)
      end

      def sort_fields(*args, &block)
        search_fields(:s, args, block)
      end

      def sort_link(attribute, *args)
        @template.sort_link @object, attribute, *args
      end

      def sort_url(attribute, *args)
        @template.sort_url @object, attribute, *args
      end

      def condition_fields(*args, &block)
        search_fields(:c, args, block)
      end

      def grouping_fields(*args, &block)
        search_fields(:g, args, block)
      end

      def attribute_fields(*args, &block)
        search_fields(:a, args, block)
      end

      def predicate_fields(*args, &block)
        search_fields(:p, args, block)
      end

      def value_fields(*args, &block)
        search_fields(:v, args, block)
      end

      def search_fields(name, args, block)
        args << {} unless args.last.is_a?(Hash)
        args.last[:builder] ||= options[:builder]
        args.last[:parent_builder] = self
        options = args.extract_options!
        objects = args.shift
        objects ||= @object.send(name)
        objects = [objects] unless Array === objects
        name = "#{options[:object_name] || object_name}[#{name}]"
        objects.inject(ActiveSupport::SafeBuffer.new) do |output, child|
          output << @template.fields_for("#{name}[#{options[:child_index] ||
          nested_child_index(name)}]", child, options, &block)
        end
      end

      def predicate_select(options = {}, html_options = {})
        options[:compounds] = true if options[:compounds].nil?
        default = options.delete(:default) || Constants::CONT

        keys =
        if options[:compounds]
          Predicate.names
        else
          Predicate.names.reject { |k| k.match(/_(any|all)$/) }
        end
        if only = options[:only]
          if only.respond_to? :call
            keys = keys.select { |k| only.call(k) }
          else
            only = Array.wrap(only).map(&:to_s)
            keys = keys.select {
              |k| only.include? k.sub(/_(any|all)$/, ''.freeze)
            }
          end
        end
        collection = keys.map { |k| [k, Translate.predicate(k)] }
        object.predicate ||= Predicate.named(default) if
          can_use_default?(default, :predicate, keys)
        template_collection_select(:p, collection, options, html_options)
      end

      def combinator_select(options = {}, html_options = {})
        template_collection_select(
          :m, combinator_choices, options, html_options)
      end

      private

      def template_grouped_collection_select(collection, options, html_options)
        @template.grouped_collection_select(
          @object_name, :name, collection, :last, :first, :first, :last,
          objectify_options(options), @default_options.merge(html_options)
          )
      end

      def template_collection_select(name, collection, options, html_options)
        @template.collection_select(
          @object_name, name, collection, :first, :last,
          objectify_options(options), @default_options.merge(html_options)
          )
      end

      def can_use_default?(default, attribute, values)
        object.respond_to?("#{attribute}=") && default &&
          values.include?(default.to_s)
      end

      def mapped_values(values)
        values.map { |v| v.is_a?(Array) ? v.first : nil }.compact
      end

      def sort_array
        [
          ['asc'.freeze,  object.translate('asc'.freeze)].freeze,
          ['desc'.freeze, object.translate('desc'.freeze)].freeze
        ].freeze
      end

      def combinator_choices
        if Nodes::Condition === object
          [
            [Constants::OR,  Translate.word(:any)],
            [Constants::AND, Translate.word(:all)]
          ]
        else
          [
            [Constants::AND, Translate.word(:all)],
            [Constants::OR,  Translate.word(:any)]
          ]
        end
      end

      def association_array(obj, prefix = nil)
        ([prefix] + association_object(obj))
        .compact
        .flat_map { |v| [prefix, v].compact.join(Constants::UNDERSCORE) }
      end

      def association_object(obj)
        case obj
        when Array
          obj
        when Hash
          association_hash(obj)
        else
          [obj]
        end
      end

      def association_hash(obj)
        obj.map do |key, value|
          case value
          when Array, Hash
            association_array(value, key.to_s)
          else
            [key.to_s, [key, value].join(Constants::UNDERSCORE)]
          end
        end
      end

      def attribute_collection_for_bases(action, bases)
        bases.map { |base| get_attribute_element(action, base) }.compact
      end

      def get_attribute_element(action, base)
        begin
          [
            Translate.association(base, :context => object.context),
            collection_for_base(action, base)
          ]
        rescue UntraversableAssociationError => e
          nil
        end
      end

      def attribute_collection_for_base(attributes, base = nil)
        attributes.map do |c|
          [
            attr_from_base_and_column(base, c),
            Translate.attribute(
              attr_from_base_and_column(base, c), :context => object.context
            )
          ]
        end
      end

      def collection_for_base(action, base)
        attribute_collection_for_base(
          object.context.send("#{action}able_attributes", base), base)
      end

      def attr_from_base_and_column(base, column)
        [base, column].reject(&:blank?).join(Constants::UNDERSCORE)
      end

      def formbuilder_error_message(action)
        "#{action.sub(Constants::SEARCH, Constants::ATTRIBUTE)
          } must be called inside a search FormBuilder!"
      end

    end
  end
end
