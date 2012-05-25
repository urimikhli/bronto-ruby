module Bronto
  class Base
    attr_accessor :id, :errors

    # Getter/Setter for global API Key.
    def self.api_key=(api_key)
      @@api_key = api_key
    end

    def self.api_key
      @@api_key
    end

    # Simple helper method to convert class name to downcased pluralized version (e.g., Field -> fields).
    def self.plural_class_name
      self.to_s.split("::").last.downcase.pluralize
    end

    # The primary method used to interface with the SOAP API.
    # This method automatically adds the required session header and returns the actual response section of the SOAP response body.
    #
    # If a symbol is passed in, it is converted to "method_plural_class_name" (e.g., :read => read_lists). A string
    # method is used as-is.
    # Pass in a block and assign a hash to soap.body with a structure appropriate to the method call.
    def self.request(method, refresh_header = false, &_block)
      _soap_header = self.soap_header(refresh_header)

      method = "#{method}_#{plural_class_name}" if method.is_a? Symbol

      resp = api.request(:v4, method.to_sym) do
        soap.header = _soap_header
        evaluate(&_block) if _block # See Savon::Client#evaluate; necessary to preserve scope.
      end

      resp.body["#{method}_response".to_sym]
    end

    # Sets up the Savon SOAP client object (if necessary) and returns it.
    def self.api
      return @api unless @api.nil?

      @api = Savon::Client.new do
        wsdl.endpoint = "https://api.bronto.com/v4"
        wsdl.namespace = "http://api.bronto.com/v4"
      end
    end

    # Helper method to retrieve the session ID and return a SOAP header.
    # Will return a header with the same initial session ID unless the `refresh` argument is `true`.
    def self.soap_header(refresh = false)
      return @soap_header if !refresh and @soap_header.present?

      resp = api.request(:v4, :login) do
        soap.body = { api_token: self.api_key }
      end

      @soap_header = { "v4:sessionHeader" => { session_id: resp.body[:login_response][:return] } }
    end

    # Saves a collection of Bronto::Base objects.
    # Objects without IDs are considered new and are `create`d; objects with IDs are considered existing and are `update`d.
    def self.save(*objs)
      update(objs.select { |o| o.errors.clear; o.id.present? })
      create(objs.select { |o| o.errors.clear; o.id.blank? })
    end

    # Finds objects matching the `filter` (a Bronto::Filter instance).
    def self.find(filter, page_number = 1)
      resp = request(:read) do
        soap.body = { filter: filter.to_hash, page_number: page_number }
      end

      Array(resp[:return]).map { |hash| new(hash) }
    end

    # Tells the remote server to create the passed in collection of Bronto::Base objects.
    # The object should implement `to_hash` to return a hash in the format expected by the SOAP API.
    #
    # Returns the same collection of objects that was passed in. Objects whose creation succeeded will be assigned the
    # ID returned from Bronto.
    def self.create(*objs)
      resp = request(:add) do
        soap.body = {
          plural_class_name => objs.map(&:to_hash)
        }
      end

      results = resp[:return][:results]
      results = [results] unless results.is_a? Array

      results.each_with_index do |result, i|
        if result[:is_new] and !result[:is_error]
          objs[i].id = result[:id]
        elsif result[:is_error]
          objs[i].errors.add(error_code, result[:error_string])
        end
      end

      objs
    end

    # Updates a collection of Bronto::Base objects. The objects should exist on the remote server.
    # The object should implement `to_hash` to return a hash in the format expected by the SOAP API.
    def self.update(*objs)
      resp = request(:update) do
        soap.body = {
          plural_class_name => objs.map(&:to_hash)
        }
      end

      objs
    end

    # Destroys a collection of Bronto::Base objects on the remote server.
    #
    # Returns the same collection of objects that was passed in. Objects whose destruction succeeded will
    # have a nil ID.
    def self.destroy(*objs)
      objs = objs.select { |o| o.id.present? }

      resp = request(:delete) do
        soap.body = {
          plural_class_name => objs.map { |o| { id: o.id }}
        }
      end

      results = resp[:return][:results]
      results = [results] unless results.is_a? Array

      results.each_with_index do |result, i|
        if result[:is_error]
          objs[i].errors.add(error_code, result[:error_string])
        else
          objs[i].id = nil
        end
      end

      objs
    end

    # Accepts a hash whose keys should be setters on the object.
    def initialize(options = {})
      self.errors = Errors.new
      options.each { |k,v| send("#{k}=", v) if respond_to?("#{k}=") }
    end

    # `to_hash` should be overridden to provide a hash whose structure matches the structure expected by the API.
    def to_hash
      {}
    end

    # Convenience instance method that calls the class `request` method.
    def request(method, &block)
      self.class.request(method, &block)
    end

    # Saves the object. If the object has an ID, it is updated. Otherwise, it is created.
    def save
      id.blank? ? create : update
    end

    # Creates the object. See `Bronto::Base.create` for more info.
    def create
      self.class.create(self).first
    end

    # Updates the object. See `Bronto::Base.update` for more info.
    def update
      self.class.update(self).first
    end

    # Destroys the object. See `Bronto::Base.destroy` for more info.
    def destroy
      self.class.destroy(self).first
    end
  end
end