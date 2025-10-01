# frozen_string_literal: true

require 'active_support/inflector'

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module EnumerationsControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :show, :create, :update, :destroy
        base.helper_method :extended_api_metadata if base.respond_to?(:helper_method)
      end

      def index
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        type = params[:type].presence

        if type
          if (enumeration = enumeration_from_identifier(type))
            @enumeration = enumeration
            return render_extended_api('enumerations/show')
          elsif numeric_identifier?(type)
            return render_api_not_found
          else
            @enumeration_sets = load_enumerations_for_type(type)
          end
        else
          @enumeration_sets = load_all_enumerations
        end

        if @enumeration_sets.nil?
          return render_api_not_found
        end

        @enumeration_sets = Array(@enumeration_sets).compact

        render_extended_api('enumerations/index')
      end

      def show
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        @enumeration = Enumeration.find(params[:id])
        render_extended_api('enumerations/show')
      rescue ActiveRecord::RecordNotFound
        render_api_not_found
      end

      def create
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        if request.post? && @enumeration.save
          render_extended_api(
            'enumerations/show',
            status: :created,
            location: enumerations_url(format: api_request_format_symbol(:json))
          )
        else
          render_api_validation_errors(@enumeration)
        end
      end

      def update
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        if @enumeration.update(enumeration_params)
          render_extended_api('enumerations/show')
        else
          render_api_validation_errors(@enumeration)
        end
      end

      def destroy
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        if !@enumeration.in_use?
          @enumeration.destroy
          mark_extended_api_response(fallback: false)
          head :no_content
        elsif params[:reassign_to_id].present? && (reassign_to = @enumeration.class.find_by_id(params[:reassign_to_id].to_i))
          @enumeration.destroy(reassign_to)
          mark_extended_api_response(fallback: false)
          head :no_content
        else
          message = I18n.t(
            :text_enumeration_destroy_question,
            name: @enumeration.name,
            count: @enumeration.objects_count
          )
          @enumeration.errors.add(:base, message)
          render_api_validation_errors(@enumeration)
        end
      end

      private

      def load_enumerations_for_type(type)
        klass = resolve_enumeration_class(type)
        return unless klass

        [build_enumeration_set(klass)]
      end

      def load_all_enumerations
        enumeration_class_candidates.map { |klass| build_enumeration_set(klass) }
      end

      def enumeration_from_identifier(identifier)
        return unless numeric_identifier?(identifier)

        find_enumeration_by_id(identifier.to_i)
      end

      def enumeration_class_candidates
        classes = []

        if Enumeration.respond_to?(:types)
          Array(Enumeration.types).each do |identifier|
            klass = resolve_enumeration_class(identifier)
            classes << klass if klass
          end
        end

        classes.concat(enumeration_descendants)

        classes.compact!
        classes.uniq!

        classes.select! do |klass|
          next false unless klass.is_a?(Class)

          unless defined?(Enumeration)
            true
          else
            klass < Enumeration
          end
        end

        classes
      end

      def enumeration_descendants
        descendants = if Enumeration.respond_to?(:descendants)
                        Enumeration.descendants
                      elsif Enumeration.respond_to?(:subclasses)
                        Enumeration.subclasses
                      else
                        []
                      end

        Array(descendants)
      end

      def build_enumeration_set(klass)
        {type: enumeration_type_key(klass), enumerations: enumerations_for_class(klass)}
      end

      def enumerations_for_class(klass)
        scope = if klass.respond_to?(:sorted)
                  klass.sorted
                elsif klass.respond_to?(:order)
                  klass.order(:position)
                elsif klass.respond_to?(:all)
                  klass.all
                else
                  []
                end

        scope.respond_to?(:to_a) ? scope.to_a : Array(scope)
      end

      def resolve_enumeration_class(identifier)
        if identifier.is_a?(Class)
          return identifier unless defined?(Enumeration)
          return identifier if identifier < Enumeration

          return nil
        end
        return nil unless identifier

        if Enumeration.respond_to?(:get_subclass)
          subclass = Enumeration.get_subclass(identifier)
          return subclass if subclass
        end

        class_name = identifier.to_s
        camelized = ActiveSupport::Inflector.camelize(class_name)
        singular_camelized = ActiveSupport::Inflector.camelize(ActiveSupport::Inflector.singularize(class_name))
        candidates = [class_name, camelized, singular_camelized]

        candidates.each do |candidate|
          begin
            klass = ActiveSupport::Inflector.constantize(candidate)
            next unless klass.is_a?(Class)

            return klass unless defined?(Enumeration)
            return klass if klass < Enumeration
          rescue NameError
            next
          end
        end

        nil
      end

      def find_enumeration_by_id(id)
        if Enumeration.respond_to?(:find_by)
          Enumeration.find_by(id: id)
        elsif Enumeration.respond_to?(:find_by_id)
          Enumeration.find_by_id(id)
        else
          Enumeration.find(id)
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def numeric_identifier?(value)
        value.to_s.match?(/\A\d+\z/)
      end

      def enumeration_type_key(klass)
        if klass.respond_to?(:model_name) && klass.model_name.respond_to?(:collection)
          klass.model_name.collection
        else
          name = klass.name.to_s.split('::').last
          underscored = ActiveSupport::Inflector.underscore(name)
          ActiveSupport::Inflector.pluralize(underscored)
        end
      end
    end
  end
end
