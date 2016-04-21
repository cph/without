require "without/version"
require "active_record"

module Without
  def without_a(belongs_to, options={})
    options = options.with_indifferent_access
    scope = all
    association = scope.model.reflect_on_association(belongs_to)

    unless association.macro == :belongs_to
      raise ArgumentError, "`without_a` only works on belongs_to associations"
    end

    if association.polymorphic?
      foreign_type = options.fetch(association.foreign_type) do
        raise ArgumentError, "`#{belongs_to}` is a polymorphic association; please " <<
                             "pass :#{association.foreign_type} to `without_a`"
      end

      join_table = foreign_type.constantize.table_name
      scope = scope.where(scope.arel_table[association.foreign_type].eq(foreign_type))
    else
      join_table = association.table_name
    end

    # This technique with the JOINs is a lot more work than simply saying
    #
    #   where("#{association.foreign_key} NOT IN (SELECT id FROM #{association.table_name})")
    #
    # but `NOT IN` is very slow: it requires a sequence scan. On very large
    # tables this thousands (or millions!) of times faster.
    query = scope.joins("LEFT OUTER JOIN #{join_table} ON #{table_name}.#{association.foreign_key}=#{join_table}.id").where("#{join_table}.id" => nil)

    # Postgres does not allow a DELETE statement to also use JOINs.
    # The common technique (that Rails uses) is to
    #
    #   DELETE FROM the_table WHERE primary_key in (the_query)
    #
    # This technique doesn't work with pure join tables which have
    # no primary key.
    #
    # So instead we manually construct a query that moves the JOIN
    # into a subquery and connects the two with a key that will work
    # (the broken foreign_key).
    unless scope.model.primary_key
      query = scope.where(association.foreign_key => query.select(association.foreign_key))
    end

    query
  end
  alias :without_an :without_a

  def without_any(has_many)
    scope = all
    association = scope.model.reflect_on_association(has_many)

    unless association.macro == :has_many
      raise ArgumentError, "`without_any` only works on has_many associations"
    end

    scope.joins("LEFT OUTER JOIN #{association.table_name} ON #{table_name}.id=#{association.table_name}.#{association.foreign_key}").where("#{association.table_name}.#{association.foreign_key}" => nil)
  end
end

ActiveRecord::Base.extend Without
