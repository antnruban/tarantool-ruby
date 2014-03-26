require 'tarantool/util'
require 'tarantool/shards_support'
require 'tarantool/serializers'

module Tarantool
  module CommonSpace
    attr_reader :tarantool, :space_no
  end

  module Request
    include Util::Packer
    include Util::TailGetter
    include Serializers
    SELECT_HEADER = 'VVVVV'.freeze
    INSERT_HEADER = 'VV'.freeze
    UPDATE_HEADER = 'VV'.freeze
    DELETE_HEADER = 'VV'.freeze
    CALL_HEADER = 'Vwa*'.freeze
    INT32_0 = "\x00\x00\x00\x00".freeze
    INT32_1 = "\x01\x00\x00\x00".freeze
    ZERO = "\x00".freeze
    ONE  = "\x01".freeze
    EMPTY = "".freeze
    PACK_STRING = 'wa*'.freeze
    LEST_INT32 = -(2**31)

    TYPES_AUTO = [:auto].freeze
    TYPES_FALLBACK = [:string].freeze
    TYPES_STR_STR = [:string, :string].freeze
    TYPES_STR_AUTO = [:string, :auto].freeze

    REQUEST_SELECT = 17
    REQUEST_INSERT = 13
    REQUEST_UPDATE = 19
    REQUEST_DELETE = 21
    REQUEST_CALL   = 22
    REQUEST_PING   = 65280

    BOX_RETURN_TUPLE = 0x01
    BOX_ADD = 0x02
    BOX_REPLACE = 0x04

    UPDATE_OPS = {
      :"=" => 0, :+   => 1, :&   => 2, :^   => 3, :|  => 4, :[]     => 5,
      :set => 0, :add => 1, :and => 2, :xor => 3, :or => 4, :splice => 5,
      :delete => 6, :insert => 7,
      :del    => 6, :ins    => 7,
       '=' => 0, '+'  => 1, '&'  => 2, '^'  => 3, '|' => 4, '[]'    => 5,
                                                            ':'     => 5,
      'set'=> 0, 'add'=> 1, 'and'=> 2, 'xor'=> 3, 'or'=> 4, 'splice'=> 5,
      '#'     => 6, '!'     => 7,
      'delete'=> 6, 'insert'=> 7,
      'del'   => 6, 'ins'   => 7,
       0 => 0, 1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => 5, 6 => 6, 7 => 7
    }
    UPDATE_FIELDNO_OP = 'VC'.freeze

    def _send_request(shard_numbers, read_write, cb)
      @tarantool._send_request(shard_numbers, read_write, cb)
    end

    BINARY = ::Encoding::BINARY
    def _select(space_no, index_no, offset, limit, keys, cb, fields, index_fields, shard_nums, translators = [])
      get_tuples = limit == :first ? (limit = 1; :first) : :all
      keys = [*keys]
      body = ::BinUtils.append_int32_le!(nil, space_no, index_no, offset, limit, keys.size)

      for key in keys
        pack_tuple(body, key, index_fields, index_no)
      end
      response = Response.new(cb, REQUEST_SELECT, body, get_tuples, fields, translators)
      _send_request(shard_nums, :read, response)
    end

    class IndexIndexError < StandardError; end
    def pack_tuple(body, key, types, index_no = 0)
      if Integer === types.last
        *types, tail = types
      else
        tail = 1
      end
      case key
      when Array
        if index_no != :space && nili = key.index(nil)
          key = key.slice(0, nili)
        end
        ::BinUtils.append_int32_le!(body, key_size = key.size)
        i = 0
        while i < key_size
          field = types[i] || get_tail_item(types, i, tail)
          pack_field(body, field, key[i])
          i += 1
        end
      when nil
        body << INT32_0
      else
        body << INT32_1
        pack_field(body, types[0], key)
      end
    rescue IndexIndexError
      raise ArgumentError, "tuple #{key} has more entries than index #{index_no}"
    end

    MAX_BYTE_SIZE = 1024 * 1024
    def pack_field(body, field_kind, value)
      if value.nil?
        body << ZERO
        return
      end
      case field_kind
      when :int, :integer
        value = value.to_i
        _raise_integer_overflow(value, MIN_INT, MAX_INT32)  if value > MAX_INT32 or value < 0
        ::BinUtils.append_bersize_int32_le!(body, value)
      when :string, :bytes, :str
        value = value.to_s
        value = ZERO + value  if value < ONE
        raise StringTooLong  if value.bytesize >= MAX_BYTE_SIZE
        ::BinUtils.append_bersize_string!(body, value)
      when :bytes
        value = value.to_s
        raise StringTooLong  if value.bytesize >= MAX_BYTE_SIZE
        ::BinUtils.append_bersize_string!(body, value)
      when :int64
        value = value.to_i
        _raise_integer_overflow(value, MIN_INT, MAX_INT64)  if value > MAX_INT64 or value < 0
        ::BinUtils.append_bersize_int64_le!(body, value)
      when :int16
        value = value.to_i
        _raise_integer_overflow(value, MIN_INT, MAX_INT16)  if value > MAX_INT16 or value < 0
        ::BinUtils.append_bersize_int16_le!(body, value)
      when :int8
        value = value.to_i
        _raise_integer_overflow(value, MIN_INT, MAX_INT8)  if value > MAX_INT8 or value < 0
        ::BinUtils.append_bersize_int8!(body, value)
      when :sint
        value = value.to_i
        _raise_integer_overflow(value, MIN_SINT32, MAX_SINT32)  if value > MAX_SINT32 or value < MIN_SINT32
        ::BinUtils.append_bersize_int32_le!(body, value)
      when :sint64
        value = value.to_i
        _raise_integer_overflow(value, MIN_SINT64, MAX_SINT64)  if value > MAX_SINT64 or value < MIN_SINT64
        ::BinUtils.append_bersize_int64_le!(body, value)
      when :sint16
        value = value.to_i
        _raise_integer_overflow(value, MIN_SINT16, MAX_SINT16)  if value > MAX_SINT16 or value < MIN_SINT16
        ::BinUtils.append_bersize_int16_le!(body, value)
      when :sint8
        value = value.to_i
        _raise_integer_overflow(value, MIN_SINT8, MAX_SINT8)  if value > MAX_SINT8 or value < MIN_SINT8
        ::BinUtils.append_bersize_int8!(body, value)
      when :varint
        value = value.to_i
        if 0 <= value && value < MAX_INT32
          ::BinUtils.append_bersize_int32_le!(body, value)
        else
          ::BinUtils.append_bersize_int64_le!(body, value)
        end
      when :error
        raise IndexIndexError
      when :auto
        case value
        when Integer
          pack_field(body, :varint, value)
        when String
          pack_field(body, :bytes, value)
        when Util::AutoType
          pack_field(body, :bytes, value.data)
        else
          raise ArgumentError, "Could auto detect only Integer and String"
        end
      else
        value = get_serializer(field_kind).encode(value).to_s
        raise StringTooLong  if value.bytesize > MAX_BYTE_SIZE
        ::BinUtils.append_bersize_string!(body, value)
      end
    end

    def _raise_integer_overflow(value, min, max)
        raise IntegerFieldOverflow, "#{value} not in (#{min}..#{max})"
    end

    def _modify_request(type, body, fields, ret_tuple, cb, shard_nums, read_write, translators)
      response = Response.new(cb, type, body, ret_tuple && (ret_tuple != :all ? :first : :all),
                            fields, translators)
      _send_request(shard_nums, read_write, response)
    end


    def _insert(space_no, flags, tuple, fields, cb, ret_tuple, shard_nums, in_any_shard = nil, translators = [])
      flags |= BOX_RETURN_TUPLE  if ret_tuple
      fields = [*fields]

      tuple = [*tuple]
      body = ::BinUtils.append_int32_le!(nil, space_no, flags)
      pack_tuple(body, tuple, fields, :space)

      _modify_request(REQUEST_INSERT, body, fields, ret_tuple, cb, shard_nums,
                      in_any_shard ? :replace : :write, translators)
    end

    def _update(space_no, pk, operations, fields, pk_fields, cb, ret_tuple, shard_nums, translators = [])
      flags = ret_tuple ? BOX_RETURN_TUPLE : 0

      if Array === operations && !(Array === operations.first)
        operations = [operations]
      end

      body = ::BinUtils.append_int32_le!(nil, space_no, flags)
      pack_tuple(body, pk, pk_fields, 0)
      ::BinUtils.append_int32_le!(body, operations.size)

      _pack_operations(body, operations, fields)

      _modify_request(REQUEST_UPDATE, body, fields, ret_tuple, cb, shard_nums, :write, translators)
    end

    def _pack_operations(body, operations, fields)
      if Integer === fields.last
        *fields, tail = fields
      else
        tail = 1
      end
      for operation in operations
        if Array === operation[0]
          operation = operation[0] + operation.drop(1)
        elsif Array === operation[1]
          if operation.size == 2
            operation = [operation[0]] + operation[1]
          else
            raise ArgumentError, "Could not understand operation #{operation}"
          end
        end

        field_no = operation[0]
        if operation.size == 2
          if (Integer === field_no || field_no =~ /\A\d/)
            unless Symbol === operation[1] && UPDATE_OPS[operation[1]] == 6
              ::BinUtils.append_int32_int8_le!(body, field_no, 0)
              type = fields[field_no] || get_tail_item(fields, field_no, tail) ||
                _detect_type(operation[1])
              pack_field(body, type, operation[1])
              next
            end
          elsif String === field_no
            operation.insert(1, field_no.slice(0, 1))
            field_no = field_no.slice(1..-1).to_i
          else
            raise ArgumentError, "Could not understand field number #{field_no.inspect}"
          end
        end

        op = operation[1]
        op = UPDATE_OPS[op]  unless Integer === op
        raise ArgumentError, "Unknown operation #{operation[1]}" unless op
        case op
        when 0
          ::BinUtils.append_int32_int8_le!(body, field_no, op)
          if (type = fields[field_no]).nil?
            if operation.size == 4 && Symbol === operation.last
              *operation, type = operation
            else
              type = get_tail_item(fields, field_no, tail) || _detect_type(operation[2])
            end
          end
          unless operation.size == 3
            raise ArgumentError, "wrong arguments for set or insert operation #{operation.inspect}"
          end
          pack_field(body, type, operation[2])
        when 1, 2, 3, 4
          ::BinUtils.append_int32_int8_le!(body, field_no, op)
          unless operation.size == 3 && !operation[2].nil?
            raise ArgumentError, "wrong arguments for integer operation #{operation.inspect}"
          end
          pack_field(body, :sint, operation[2])
        when 5
          ::BinUtils.append_int32_int8_le!(body, field_no, op)
          unless operation.size == 5 && !operation[2].nil? && !operation[3].nil?
            raise ArgumentError, "wrong arguments for slice operation #{operation.inspect}"
          end

          str = operation[4].to_s
          ::BinUtils.append_ber!(body, 10 + ber_size(str.bytesize) + str.bytesize)
          ::BinUtils.append_bersize_int32_le!(body, operation[2].to_i)
          ::BinUtils.append_bersize_int32_le!(body, operation[3].to_i)
          ::BinUtils.append_bersize_string!(body, str.to_s)
        when 7
          old_field_no = field_no +
            (inserted ||= []).count{|i| i <= field_no} -
            (deleted ||= []).count{|i| i <= field_no}
          ::BinUtils.append_int32_int8_le!(body, old_field_no, op)
          inserted << field_no
          if (type = fields[old_field_no]).nil?
            if operation.size == 4 && Symbol === operation.last
              *operation, type = operation
            else
              type = get_tail_item(fields, old_field_no, tail)
            end
          end
          unless operation.size == 3
            raise ArgumentError, "wrong arguments for set or insert operation #{operation.inspect}"
          end
          pack_field(body, type, operation[2])
        when 6
          old_field_no = field_no +
            (inserted ||= []).count{|i| i <= field_no} -
            (deleted ||= []).count{|i| i <= field_no}
          ::BinUtils.append_int32_int8_le!(body, old_field_no, op)
          deleted << field_no
          body << ZERO
          # pass
        end
      end
    end

    def _delete(space_no, pk, fields, pk_fields, cb, ret_tuple, shard_nums, translators = [])
      flags = ret_tuple ? BOX_RETURN_TUPLE : 0

      body = ::BinUtils.append_int32_le!(nil, space_no, flags)
      pack_tuple(body, pk, pk_fields, 0)

      _modify_request(REQUEST_DELETE, body, fields, ret_tuple, cb, shard_nums, :write, translators)
    end

    def _space_call_fix_values(values, space_no, opts)
      opts = opts.dup
      space_no = opts[:space_no]  if opts.has_key?(:space_no)
      if space_no
        values = [space_no].concat([*values])
        if opts[:types]
          opts[:types] = [:string].concat([*opts[:types]]) # cause lua could convert it to integer by itself
        else
          opts[:types] = TYPES_STR_STR
        end
      end

      # scheck for shards hints
      opts[:shards] ||= _get_shard_nums do
          if opts[:shard_for_insert]
            opts[:shard_keys] ? _detect_shards_for_insert(opts[:shard_keys]) :
            opts[:shard_key]  ? _detect_shard_for_insert( opts[:shard_key]) :
                                 _all_shards
          else
            opts[:shard_keys] ? _detect_shards(opts[:shard_keys]) :
            opts[:shard_key]  ? _detect_shard( opts[:shard_key]) :
                                 _all_shards
          end
        end
      [values, opts]
    end

    def _call(func_name, values, cb, opts={})
      return_tuple = opts[:return_tuple] && :all
      flags = return_tuple ? BOX_RETURN_TUPLE : 0
      
      values = [*values]
      value_types = opts[:types] ? [*opts[:types]] :
                                  _detect_types(values)
      return_types = [*opts[:returns] || TYPES_AUTO]

      func_name = func_name.to_s
      body = ::BinUtils.append_int32_le!(nil, flags)
      ::BinUtils.append_bersize_string!(body, func_name)
      pack_tuple(body, values, value_types, :func_call)

      shard_nums = opts[:shards] || all_shards
      read_write = case opts[:readonly]
                   when nil, false, :write
                     :write
                   when true, :read
                     :read
                   when :replace
                     :replace
                   else
                     raise ArgumentError, "space#call :readonly options accepts nil, false, :write, true, :read and :replace, but #{opts[:readonly].inspect} were sent"
                   end

      _modify_request(REQUEST_CALL, body, return_types, return_tuple, cb, shard_nums, read_write, opts[:translators] || [])
    end

    class WrapPing < Struct.new(:cb)
      def call(data)
        cb.call data
      end
      def call_callback(data)
        cb.call data
      end
      def parse_response(data)
        data
      end
      def parse_response_for_cb(data)
        data
      end
    end
    def _ping(cb)
      _send_request(all_shards, :write, REQUEST_PING, EMPTY, WrapPing.new(cb))
    end
    alias ping_cb _ping

    def _detect_types(values)
      values.map{|v| Integer === v ? :varint : :string}
    end

    def _detect_type(value)
      Integer === v ? :varint :
      Util::AutoType === v ? :auto :
      :string
    end

    def _parse_hash_definition(returns)
      field_names = []
      field_types = []
      returns.each{|name, type|
        field_names << name
        field_types << type
      }
      field_types << if field_names.include?(:_tail)
          unless field_names.last == :_tail
            raise ArgumentError, "_tail should be de declared last"
          end
          field_names.pop
          [*field_types.last].size
        else
          1
        end
      field_types.flatten!
      [field_types, TranslateToHash.new(field_names, field_types.last)]
    end

    def _raise_or_return(res)
      raise res  if Exception === res
      res
    end
  end

  module CommonSpaceBlockMethods
    def all_by_pks_blk(keys, opts={}, &block)
      all_by_pks_cb(keys, block, opts)
    end

    def by_pk_blk(key_array, &block)
      by_pk_cb(key_array, block)
    end

    def insert_blk(tuple, opts={}, &block)
      insert_cb(tuple, block, opts)
    end

    def replace_blk(tuple, opts={}, &block)
      replace_cb(tuple, block, opts)
    end

    def store_blk(tuple, opts={}, &block)
      store_cb(tuple, block, opts)
    end

    def update_blk(pk, operations, opts={}, &block)
      update_cb(pk, operations, block, opts)
    end

    def delete_blk(pk, opts={}, &block)
      delete_cb(pk, block, opts)
    end

    def invoke_blk(func_name, values = [], opts={}, &block)
      invoke_cb(func_name, values, block, opts)
    end

    def call_blk(func_name, values = [], opts={}, &block)
      call_cb(func_name, values, block, opts)
    end

    def ping_blk(&block)
      ping_cb(block)
    end
  end

end
