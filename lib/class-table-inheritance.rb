require 'active_record'
require 'inherits-migration'

# ClassTableInheritance is an ActiveRecord plugin designed to allow 
# simple multiple table (class) inheritance.
class ActiveRecord::Base  
  attr_reader :reflection
      
  def self.acts_as_subclass
    if self.column_names.include?("type")
      def self.find(*args)
        old = super
        puts self.inspect
        if !old[:type].nil? && !old[:type].blank?
          inherits_type = Object.const_get(old[:type].to_s)
          inherits_type.send(:find, *args)
        else
          super
        end
      end
    end  
  end
      
  def self.inherits_from(association_id)

    # add an association, and set the foreign key.
    has_one association_id, :foreign_key => :id


    # set the primary key, it' need because the generalized table doesn't have
    # a field ID.
    set_primary_key "#{association_id}_id"


    # Autobuild method to make a instance of association
    define_method("#{association_id}_with_autobuild") do
      send("#{association_id}_without_autobuild") || send("build_#{association_id}")
    end

    
    # Set a method chain whith autobuild.
    alias_method_chain association_id, :autobuild    

    
    # bind the before save, this method call the save of association, and
    # get our generated ID an set to association_id field.
    before_save :save_inherit
    
    
    # Bind the validation of association.
    validate :inherit_association_must_be_valid    


    # Generate a method to validate the field of association.    
    define_method("inherit_association_must_be_valid") do
      association = send(association_id)

      unless valid = association.valid?
        association.errors.each do |attr, message|
          errors.add(attr, message)
        end
      end
      
      valid
    end    
          
    
    
    # get the class of association by reflection, this is needed because
    # i need to get the methods and attributes to make a proxy methods.
    reflection = create_reflection(:has_one, association_id, {}, self)
    association_class = Object.const_get(reflection.class_name)    
    # Get the colluns of association class.
    inherited_columns = association_class.column_names
    # Make a filter in association colluns to exclude the colluns that
    # the generalized class already have.
    inherited_columns = inherited_columns.reject { |c| self.column_names.grep(c).length > 0 || c == "type" }
    # Get the methods of the association class and tun it to an Array of Strings.
    inherited_methods = association_class.reflections.map { |key,value| key.to_s }
    # Make a filter in association methods to exclude the methods that
    # the generalizae class already have.
    inherited_methods = inherited_methods.reject { |c| self.reflections.map {|key, value| key.to_s }.include?(c) }
    
    
    # create the proxy methods to get and set the properties and methods
    # in association class.
    (inherited_columns + inherited_methods).each do |name|
    	define_method name do
	  	  # if the field is ID than i only bind that with the association field.
	  	  # this is needed to bypass the overflow problem when the ActiveRecord
	  	  # try to get the id to find the association.
    	  if name == 'id'
    	    self["#{association_id}_id"]
    	  else 
          assoc = send(association_id)
          assoc.send(name)
        end
    	end
  
    	
    	define_method "#{name}=" do |new_value|
	  	  # if the field is ID than i only bind that with the association field.
	  	  # this is needed to bypass the overflow problem when the ActiveRecord
	  	  # try to get the id to find the association.
    	  if name == 'id'
    	    self["#{association_id}_id"] = new_value
    	  else     	  
          assoc = send(association_id)
          assoc.send("#{name}=", new_value)
        end
    	end
    end


    # Create a method do bind in before_save callback, this method
    # only call the save of association class and set the id in the
    # generalized class.
    define_method("save_inherit") do |*args|
      association = send(association_id)
      if !association.column_for_attribute("type").nil?
        association.type = self.class.to_s
      end
      
      association.save
      self["#{association_id}_id"] = association.id
      true
    end
  end
end