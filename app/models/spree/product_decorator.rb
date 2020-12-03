module Spree::ProductDecorator
  def self.prepended(base)
    base.searchkick(
      callbacks: :async,
      word_start: [:name],
      settings: { number_of_replicas: 0 },
      merge_mappings: true,
      mappings: {
        properties: {
          properties: {
            type: 'nested'
          }
        }
      }
    ) unless base.respond_to?(:searchkick_index)

    base.scope :search_import, lambda {
      includes(
        :option_types,
        :variants_including_master,
        taxons: :taxonomy,
        master: :default_price,
        product_properties: :property,
        variants: :option_values
      )
    }

    def base.autocomplete_fields
      [:name]
    end

    def base.search_fields
      [:name]
    end

    def base.autocomplete(keywords)
      if keywords
        Spree::Product.search(
          keywords,
          fields: autocomplete_fields,
          match: :word_start,
          limit: 10,
          load: false,
          misspellings: { below: 3 },
          where: search_where,
        ).map(&:name).map(&:strip).uniq
      else
        Spree::Product.search(
          "*",
          fields: autocomplete_fields,
          load: false,
          misspellings: { below: 3 },
          where: search_where,
        ).map(&:name).map(&:strip)
      end
    end

    def base.search_where
      {
        active: true,
        price: { not: nil },
      }
    end
  end

  def search_data
    all_taxons = taxons.map { |t| t.self_and_ancestors.pluck(:id, :name) }.flatten.uniq
    filtered_option_types = option_types.filterable.pluck(:id, :name)
    json = {
      id: id,
      name: name,
      description: description,
      active: available?,
      created_at: created_at,
      updated_at: updated_at,
      price: price,
      currency: currency,
      conversions: orders.complete.count,
      taxon_ids: all_taxons.map(&:first),
      taxon_names: all_taxons.map(&:last),
      option_type_ids: filtered_option_types.map(&:first),
      option_type_names: filtered_option_types.map(&:last),
      option_value_ids: variants.map { |v| v.option_value_ids }.flatten.compact.uniq,
      skus: variants_including_master.pluck(:sku),
      properties: properties.filterable.map { |prop| { id: prop.id, name: prop.name, value: property(prop.name) } }
    }

    loaded(:product_properties, :property).each do |prod_prop|
      json.merge!(Hash[prod_prop.property.name.downcase, prod_prop.value])
    end

    option_types.each do |option_type|
      json.merge!(
        Hash[
          option_type.name.downcase,
          variants.map { |v| v.option_values.find_by(option_type: option_type)&.name }.compact.uniq
        ]
      )
    end

    loaded(:taxons, :taxonomy).group_by(&:taxonomy).map do |taxonomy, taxons|
      json.merge!(Hash["#{taxonomy.name.downcase}_ids", taxon_by_taxonomy(taxonomy.id).map(&:id)])
    end

    json.merge!(index_data)

    json
  end

  def index_data
    {}
  end

  def loaded(prop, incl)
    relation = send(prop)
    relation.loaded? ? relation : relation.includes(incl)
  end
end

Spree::Product.prepend(Spree::ProductDecorator)
