# coding: utf-8
#
# OAK: An encoding format with enough polymorphism to support run-time
# performance experimentation and some light encryption-at-rest.
#
# author: jhw@prosperworks.com
# incept: 2016-03-02

require_relative 'oak/version'
require          'strscan'
require          'digest'
require          'base64'
require          'lz4-ruby'
require          'zlib'
require          'bzip2/ffi'
require          'lzma'
require          'openssl'

module OAK

  # CantTouchThisObjectError is thrown when encode() or serialize() is
  # called on an object which cannot be encoded losslessly by OAK.
  #
  class CantTouchThisObjectError < ArgumentError ; end

  # CantTouchThisStringError is thrown when decode(), deserialize(),
  # or unwrap() called on a String which cannot be decoded.
  #
  class CantTouchThisStringError < ArgumentError ; end

  # Internal syntactic conveniences.
  #
  BAD_OBJ = CantTouchThisObjectError
  BAD_STR = CantTouchThisStringError

  # OAK_4 supports one and only one encryption algorithm and mode of
  # operation.
  #
  #   - AES-256-GCM
  #     - 128 bits of security
  #     - 256-bit keys      (32 bytes)
  #     -  96-bit IVs       (12 bytes)
  #     - 128-bit auth_tags (16 bytes)
  #   - Random IV ("Initialization Vector") for each encryption op
  #   - All headers authenticated.
  #   - Headers encrypted when not required for decryption.
  #
  ENCRYPTION_ALGO_NAME           = 'aes-256-gcm'.freeze
  ENCRYPTION_ALGO_IV_BYTES       = 12 # AES-256-GCM has  96-bit IVs
  ENCRYPTION_ALGO_AUTH_TAG_BYTES = 16 # AES-256-GCM has 128-bit auth, we use all

  # Get a new instance of OpenSSL::Cipher for our algorithm.
  #
  def self.encryption_algo
    OpenSSL::Cipher.new(ENCRYPTION_ALGO_NAME)
  end

  # Generate a new random key appropriate for the OAK_4 encryption
  # algorithm.
  #
  def self.random_key
    encryption_algo.random_key
  end

  # Generate a new random initialization vector appropriate for the
  # OAK_4 encryption algorithm.
  #
  def self.random_iv
    encryption_algo.random_iv
  end

  class Key

    # @param key String encryption key suitable for AES-256,
    # specifically a binary string of 32 bytes (256 bits),
    # randomly-generated and kept very, very secret.
    #
    def initialize(key)
      if !key.is_a?(String)
        raise ArgumentError, "bad non-String key: ELIDED"
      end
      rk_size = OAK.random_key.size
      if key.size != rk_size
        raise ArgumentError, "bad key ELIDED, length not #{rk_size}"
      end
      @key = key.dup.freeze # happy :)
    end

    attr_reader :key

    def inspect
      #
      # Avoid exposing the key in casual logs or console session.
      #
      to_s[0..-2] + " @key=ELIDED>"
    end

  end

  class KeyChain

    def initialize(keys)
      if !keys.is_a?(Hash)
        raise ArgumentError, "bogus keys #{keys}"
      end
      keys.each do |k,v|
        if !k.is_a?(String)
          raise ArgumentError, "bogus key #{k} in keys #{keys}"
        end
        if /^[a-zA-Z][0-9a-zA-Z]*$/ !~ k
          #
          # In oak_4, we restrict key names to sequences which look
          # like code identifiers: alphanumeric strings which start
          # with a letter.
          #
          # This keeps the encoding simple but compact.
          #
          raise ArgumentError, "bad key #{k} in keys #{keys}"
        end
        if !v.is_a?(Key)
          raise ArgumentError, "bogus val #{v} at #{k} in keys #{keys}"
        end
      end
      #
      # We are a happy KeyChain object now!
      #
      @keys = keys.dup.freeze
    end

    attr_reader :keys

  end

  # Parses a KeyChain object and keys from an ENV-like object.
  #
  # E.g. if the ENV contains:
  #
  #   FOO_KEYS=a,b
  #   FOO_KEY_a=#{OAK.encode(<binary key>)}
  #   FOO_KEY_b=#{OAK.encode(<binary key>)}
  #
  # ...then the call OAK.parse_key_chain(ENV,'FOO') will return a new
  # OAK::KeyChain with two OAK::Keys, 'a' and 'b'.
  #
  # This self-referential (but not recursive!) use of OAK to encode
  # the key and iv is to avoid the problems with binary strings in ENV
  # variables, 'heroku config:set' command line arguments, etc.
  #
  # @param env ENV or an ENV-like Hash from String to String.
  #
  # @param name String the root token
  #
  # @returns a new OAK::KeyChain
  #
  def self.parse_env_chain(env,name)
    key_names = (env["#{name}_KEYS"] || '').gsub(/^[, ]*/,'').split(/[ ,]+/)
    keys      = key_names.map do |key_name|
      key     = OAK.decode(env["#{name}_KEY_#{key_name}"] || '')
      [ key_name, Key.new(key) ]
    end.to_h
    KeyChain.new(keys)
  end

  ##########################################################################
  #
  # encode() and decode() are the top layer
  #
  # They coordinate the structure layer and the byte layer.
  #
  # These are the recommended entry points for most callers.
  #
  ##########################################################################

  # Encodes suitable objects string into OAK strings.
  #
  # Is inverted by decode().  For all obj, if encode(obj) does not
  # raise an exception, decode(encode(obj)) == obj.
  #
  # @param obj to encode
  #
  # @param redundancy    'none', 'crc32' (default), or 'sha1'
  #
  # @param compression   'none' (default), 'lz4', 'zlib', 'bzip2', 'lzma'
  #
  # @param force         false (default), or true.  When true, always
  #                      compress.  When false, fall back to the
  #                      original if the compressed form is larger.
  #
  # @param key_chain     OAK::KeyChain from which to draw the encryption
  #                      key, or nil for none.
  #
  # @param key           String name of a key in key_chain to be used
  #                      for encryption, or nil if none.
  #
  # @param format        'none', 'base64' (default)
  #
  # @param force_oak_4   Bool, for debugging, force oak_4 encoding even
  #                      if no encryption key is specified.
  #
  # @param debug_iv      String, force encryption with a known IV, TEST ONLY!
  #
  # WARNING: Use of debug_iv jeopardizes the security of all messages
  # *ever* encrypted with that key!  Never use debug_iv in production!
  #
  # @raises ArgumentError if obj is not handled.
  #
  def self.encode(obj,opts={})
    ser = _serialize(obj)
    _wrap(ser,opts)
  end

  # Decodes suitable OAK strings into objects.
  #
  # Inverts encode().
  #
  # @param str String to decode
  #
  # @param key_chain OAK::KeyChain in which to look for keys to
  # decrypt encrypted OAK strings, or nil for none.
  #
  # @returns obj String to decode
  #
  # @raises ArgumentError if str is not a recognized string.
  #
  def self.decode(str,opts={})
    if !str.is_a?(String)
      raise ArgumentError, "str not a String"
    end
    ser = _unwrap(str,opts)
    _deserialize(ser)
  end

  ##########################################################################
  #
  # serialize() and deserialize() are the structure layer
  #
  # They are responsible for interconverting between objects and naive
  # strings.
  #
  # This layer is analagous to TAR for files or JSON: it converts
  # structure into string and vice-versa.
  #
  ##########################################################################

  # Serializes suitable objects string into naive strings.
  #
  # Is inverted by deserialize().  For all obj, if serialize(obj) does
  # not raise an exception, deserialize(serialize(obj)) == obj.
  #
  # @raises CantTouchThisObjectError if obj contains any types or
  # structure which cannot be encoded reversibly by OAK.
  #
  def self._serialize(obj)
    seen,_reseen = _safety_dance(obj) do |child|
      next if ALL_TYPES.select{ |type| child.is_a?(type) }.size > 0
      raise CantTouchThisObjectError, "#{child.class} not supported: #{child}"
    end
    strt   = Hash.new # string table, str => id for strings already encoded
    ser    = 'F'
    ser   << seen.size.to_s
    seen.each_with_index do |(_object_id,(_idx2,child)),_idx|
      #
      # First, identify the unique apex type in TYPE_2_CODE.keys
      # which matches the child.
      #
      # child.class may not be listed explicitly, such as for Fixnum
      # and Bigint both being Integer, so we search and assert
      # uniqueness and existence.
      #
      is_as    = ALL_TYPES.select{ |type| child.is_a?(type) }
      raise CantTouchThisObjectError if 1 != is_as.size
      type     = is_as[0]
      typecode = TYPE_2_CODE[type]
      if nil == child || true == child || false == child
        #
        # The type code by itself is sufficient to decode NilType,
        # TrueType, and FalseType. We need use other space for them.
        #
        ser   << typecode
        next
      end
      if child.is_a?(Symbol) || child.is_a?(String)
        #
        # Strings and Symbols encode as their size in chars followed
        # by their bytes.
        #
        # We maintain a running string table, strt, to recognize when
        # we encounter a string representation which has been
        # previously encoded.
        #
        # If we find such a duplicate, we encode the current string
        # via a back reference to the first one we saw.  This is
        # indicated by downcasing the typecode.
        #
        str = child.to_s
        enc        = str.encoding
        enc_code   = nil
        case enc
        when Encoding::ASCII_8BIT, Encoding::US_ASCII, Encoding::ASCII
          enc_code = 'A'
        when Encoding::UTF_8
          enc_code = 'U'
        else
          raise CantTouchThisObjectError, "unknown string encoding #{enc}"
        end
        if strt.has_key?(str)
          ser   << typecode.downcase   # downcase indicates strt reference
          ser   << enc_code
          ser   << strt[str].to_s
        else
          ser   << typecode            # upcase indicates full representation
          ser   << enc_code
          ser   << str.bytesize.to_s
          if str.bytesize > 0
            ser << '_'
            ser << str
          end
          strt[str] = strt.size
        end
        next
      end
      if child.is_a?(Numeric)
        #
        # Numerics primitives encode as their Ruby to_s which
        # matches their JSON.dump().
        #
        ser   << typecode
        ser   << child.to_s
        next
      end
      if child.is_a?(Array)
        #
        # An array is encoded as a size N followed by N indexes into
        # the seen list.
        #
        ser   << typecode
        ser   << child.size.to_s
        child.each do |a|
          ser << '_'
          ser << seen[a.object_id][0].to_s
        end
        next
      end
      if child.is_a?(Hash)
        #
        # An array is encoded as a size N followed by 2*N indexes
        # into the seen list, organized pairwise key+value.
        #
        ser   << typecode
        ser   << child.size.to_s
        child.each do |k,v|
          ser << '_'
          ser << seen[k.object_id][0].to_s
          ser << '_'
          ser << seen[v.object_id][0].to_s
        end
        next
      end
      raise CantTouchThisObjectError, "not handled: #{child.class} #{child}"
    end
    ser
  end

  # Deserializes suitable naive strings into objects.
  #
  # Inverts serialize().
  #
  # @raises CantTouchThisObjectError if str is not recognized
  #
  def self._deserialize(str)
    scanner      = StringScanner.new(str)
    serial_code  = scanner.scan(/F/)
    if 'F' != serial_code
      raise CantTouchThisStringError, "bogus serial_code #{serial_code}"
    end
    num_objs = scanner.scan(/[0-9]+/)
    if !num_objs
      raise CantTouchThisStringError, "missing object list size"
    end
    num_objs = num_objs.to_i
    strt     = Hash.new # string table, id => str for strings already decoded
    seen     = []
    #
    # We parse the stream, constructing all the objects we see in to
    # a seen list.
    #
    # In this first pass, Arrays and Hashes are created whose
    # elements, keys, and values are temporarily integers.  These all
    # refer to slots in the seen list, and many of them will be
    # forward references to objects which we have yet to decode.
    # Later we will rectify the object graph by replacing these
    # integers with their refrants from the seen list.
    #
    num_objs.times.each do |idx_obj|
      code             = scanner.scan(/[a-zA-Z]/)
      case code
      when 'n'
        seen[idx_obj]  = nil
      when 'f'
        seen[idx_obj]  = false
      when 't'
        seen[idx_obj]  = true
      when 'S', 'Y', 's', 'y'
        enc_code       = scanner.scan(/[AU]/)
        enc            = nil
        case enc_code
        when 'A'
          enc          = Encoding::ASCII_8BIT
        when 'U'
          enc          = Encoding::UTF_8
        else
          raise CantTouchThisStringError, "unknown enc_code #{enc_code}"
        end
        num            = scanner.scan(/[0-9]+/)
        if !num
          raise CantTouchThisStringError, "missing num"
        end
        num            = num.to_i
        case code
        when 'S', 'Y'
          if num > 0
            scanner.scan(/_/) or raise BAD_STR, "missing _"
            seen[idx_obj] = scanner.peek(num)
            scanner.pos  += num                                     # skip body
          else
            seen[idx_obj] = ''
          end
          strt[strt.size] = seen[idx_obj]
        when 's', 'y'
          seen[idx_obj]   = strt[num]
        end
        seen[idx_obj]     = seen[idx_obj].dup.force_encoding(enc)
        case code
        when 'Y', 'y'
          seen[idx_obj]   = seen[idx_obj].intern
        end
      when 'I'
        pattern        = /-?[0-9]+/
        seen[idx_obj]  = scanner.scan(pattern).to_i
      when 'F'
        pattern        = /-?(Infinity|NaN|[0-9]+(\.[0-9]*)?(e([+-][0-9]*)?)?)/
        match          = scanner.scan(pattern)
        case match
        when 'Infinity'  then seen[idx_obj] = Float::INFINITY
        when '-Infinity' then seen[idx_obj] = -Float::INFINITY
        when 'NaN'       then seen[idx_obj] = Float::NAN
        else                  seen[idx_obj] = match.to_f
        end
      when 'A'
        num_items      = scanner.scan(/[0-9]+/).to_i
        arr            = []
        num_items.times.each do |idx|
          scanner.scan(/_/) or raise BAD_STR, "missing _"
          val          = scanner.scan(/[0-9]+/).to_i                # temp obj
          arr[idx]     = val
        end
        seen[idx_obj]  = arr
      when 'H'
        num_items      = scanner.scan(/[0-9]+/).to_i
        hash           = Hash.new
        num_items.times.each do
          scanner.scan(/_/) or raise BAD_STR, "missing _"
          k            = scanner.scan(/[0-9]+/).to_i                # temp obj
          scanner.scan(/_/) or raise BAD_STR, "missing _"
          v            = scanner.scan(/[0-9]+/).to_i                # temp obj
          hash[k]      = v
        end
        seen[idx_obj]  = hash
      else
        raise BAD_STR, "not handled: #{code} #{scanner.pos} #{scanner.rest}"
      end
    end
    #
    # If we parsed correctly, there will be no unconsumed in the
    # scanner.
    #
    if !scanner.eos?
      raise BAD_STR, "not at end-of-string: #{scanner.pos} #{scanner.rest}"
    end
    #
    # We rectify the references for each intermediate Array and Hash
    # as promised earlier.
    #
    # Note that this code must be inherently mutation-oriented since
    # it might have to construct cyclic graphs.
    #
    rectified = seen.map do |elem|
      if elem.is_a?(Array)
        next Array.new
      elsif elem.is_a?(Hash)
        next Hash.new
      else
        elem
      end
    end
    rectified.each_with_index do |elem,idx|
      if elem.is_a?(Array)
        seen[idx].each_with_index do |a,i|
          elem[i] = rectified[a]
        end
      elsif elem.is_a?(Hash)
        seen[idx].each do |k,v|
          elem[rectified[k]] = rectified[v]
        end
      end
    end
    #
    # By the way _safety_dance performed its walk in _serialize(), the
    # object we are decoding is the first object encoded in str.
    #
    # Thus, we return the first element of the rectified list.
    #
    rectified.first
  end

  ##########################################################################
  #
  # wrap() and unwrap() are the byte layer
  #
  # They are responsible for interconverting between naive strings and
  # strings which are ready to go out on the wire into external
  # storage.
  #
  # This layer is analagous to GZIP: it converts strings into a
  # different representation which is smaller, more resistant to
  # corruption, and/or more recognizable.
  #
  ##########################################################################

  # Wraps any string into a OAK string.
  #
  # Is inverted by unwrap().  For all str, unwrap(wrap(str)) == str.
  #
  # @param str           naive string to be wrapped as an OAK string
  #
  # @param redundancy    'none', 'crc32' (default), or 'sha1'
  #
  # @param compression   'none' (default), 'lz4', 'zlib', 'bzip2', or 'lzma'
  #
  # @param force         false (default), or true.  When true, always
  #                      compress.  When false, fall back to the
  #                      original if the compressed form is larger.
  #
  # @param key_chain     OAK::KeyChain from which to draw the encryption
  #                      key, or nil for none.
  #
  # @param key           String name of a key in key_chain to be used
  #                      for encryption, or nil if none.
  #
  # @param force_oak_4   Bool, for debugging, force oak_4 encoding even
  #                      if no encryption key is specified.
  #
  # @param format        'none', 'base64' (default)
  #
  # @returns an OAK string
  #
  def self._wrap(str,opts={})
    redundancy               = (opts[:redundancy]  || :crc32).to_s
    compression              = (opts[:compression] || :none).to_s
    force                    = (opts[:force]       || false)
    format                   = (opts[:format]      || :base64).to_s
    key_chain                = opts[:key_chain]
    key                      = opts[:key]
    debug_iv                 = opts[:debug_iv]
    if key_chain && !key_chain.is_a?(KeyChain)
      raise ArgumentError, "bad key_chain #{key_chain}"
    end
    if debug_iv && !debug_iv.is_a?(String)
      raise ArgumentError, "bad debug_iv #{debug_iv}"
    end
    if debug_iv && ENCRYPTION_ALGO_IV_BYTES != debug_iv.size
      raise ArgumentError, "bad debug_iv #{debug_iv}"
    end
    if key && !key_chain
      raise ArgumentError, "key #{key} without key_chain"
    end
    if key && !key_chain.keys[key]
      keys = key_chain.keys
      raise ArgumentError, "key not found in #{keys}: #{key}"
    end
    encryption_key           = key ? key_chain.keys[key] : nil
    str                      = str.b # dupe to Encoding::ASCII_8BIT
    if encryption_key || opts[:force_oak_4]
      _wrap_oak_4(
        str,
        redundancy,
        compression,
        force,
        format,
        key,
        encryption_key,
        debug_iv
      )
    else
      _wrap_oak_3(
        str,
        redundancy,
        compression,
        force,
        format
      )
    end
  end

  def self._wrap_oak_3(
        str,
        redundancy,
        compression,
        force,
        format
      )
    source_redundancy        = _check(redundancy,str)
    compressed, compression  = _compress(compression,force,str)
    formatted                = _format(format,compressed)
    output                   = 'oak_3'                         # format id+ver
    output                  << REDUNDANCY_2_CODE[redundancy]   # redundancy
    output                  << COMPRESSION_2_CODE[compression] # compression
    output                  << FORMAT_2_CODE[format]           # format
    output                  << '_'
    output                  << source_redundancy               # source check
    output                  << '_'
    output                  << '%d' % formatted.size           # formatted size
    output                  << '_'
    output                  << formatted                       # payload
    output                  << '_'
    output                  << 'ok'                            # terminator
    output.force_encoding(Encoding::ASCII_8BIT)
  end

  def self._wrap_oak_4(
        str,
        redundancy,
        compression,
        force,
        format,
        key,
        encryption_key,
        debug_iv
      )
    header                   = 'oak_4'                         # format id+ver
    if key
      header                << key                             # key name
    end
    header                  << '_'
    header                  << FORMAT_2_CODE[format]           # format
    compressed, compression  = _compress(compression,force,str)
    plaintext                = ''
    plaintext               << REDUNDANCY_2_CODE[redundancy]   # redundancy
    plaintext               << COMPRESSION_2_CODE[compression] # compression
    plaintext               << _check(redundancy,str)          # source check
    plaintext               << '_'
    plaintext               << compressed
    encrypted                = _encrypt(
      encryption_key,
      plaintext,
      header,
      debug_iv
    )
    formatted                = _format(format,encrypted)
    output                   = header
    output                  << '%d' % formatted.size           # formatted size
    output                  << '_'
    output                  << formatted                       # payload
    output                  << '_'
    output                  << 'ok'                            # terminator
    output.force_encoding(Encoding::ASCII_8BIT)
  end

  # Unwraps any OAK string into a string.
  #
  # Inverts wrap().  For all str, unwrap(wrap(str)) == str.
  #
  # @param str OAK string to be unwrapped
  #
  # @param key_chain OAK::KeyChain in which to look for keys to
  # decrypt encrypted OAK strings, or nil for none.
  #
  # @returns a string
  #
  # @raises ArgumentError if str is not in OAK format.
  #
  def self._unwrap(str,opts={})
    str         = str.b                   # str.b for dup to ASCII_8BIT
    sc          = StringScanner.new(str)
    ov          = sc.scan(/oak_[34]/)  or raise BAD_STR, "bad oak+ver"
    if 'oak_4' == ov
      _unwrap_oak_4(sc,opts) # encryption opts possible for decoding OAK_4 :(
    else
      _unwrap_oak_3(sc)      # no opts for decoding OAK_3 :)
    end
  end

  def self._unwrap_oak_3(sc)
    r           = sc.scan(/[NCS]/)     or raise BAD_STR, "bad redundancy"
    c           = sc.scan(/[N4ZBM]/)   or raise BAD_STR, "bad compression"
    f           = sc.scan(/[NB]/)      or raise BAD_STR, "bad format"
    _           = sc.scan(/_/)         or raise BAD_STR, "missing _"
    scheck      = sc.scan(/[a-f0-9]+/) or raise BAD_STR, "bad scheck"
    _           = sc.scan(/_/)         or raise BAD_STR, "missing _"
    fsize       = sc.scan(/[0-9]+/)    or raise BAD_STR, "bad fsize"
    fsize       = fsize.to_i
    _           = sc.scan(/_/)         or raise BAD_STR, "missing _"
    formatted   = sc.peek(fsize)
    begin
      sc.pos   += fsize
    rescue RangeError => ex
      raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
    end
    _           = sc.scan(/_ok$/)      or raise BAD_STR, "bad ok: #{formatted}"
    redundancy  = CODE_2_REDUNDANCY[r]  || r
    compression = CODE_2_COMPRESSION[c] || c
    format      = CODE_2_FORMAT[f]      || f
    fsize_re    = formatted.size
    if fsize.to_i != fsize_re
      raise CantTouchThisStringError, "fsize #{fsize} vs #{fsize_re}"
    end
    compressed  = _deformat(format,formatted)
    original    = _decompress(compression,compressed)
    scheck_re   = _check(redundancy,original)
    if scheck != scheck_re
      raise CantTouchThisStringError, "scheck #{scheck} vs #{scheck_re}"
    end
    original
  end

  def self._unwrap_oak_4(sc,opts={})
    key            = sc.scan(/[^_]+/)     # nil OK, indicates no compression
    encryption_key = nil
    if key
      key_chain    = opts[:key_chain]
      if !key_chain
        raise CantTouchThisStringError, "key #{key} but no key_chain"
      end
      encryption_key = opts[:key_chain].keys[key]
      if !encryption_key
        keys = key_chain.keys
        raise CantTouchThisStringError, "key not found in #{keys}: #{key}"
      end
    end
    _              = sc.scan(/_/)         or raise BAD_STR, "missing _"
    f              = sc.scan(/[NB]/)      or raise BAD_STR, "bad format"
    header         = sc.string[0..(sc.pos-1)] # for authentication by _decrypt
    format         = CODE_2_FORMAT[f]
    fsize          = sc.scan(/[0-9]+/)    or raise BAD_STR, "bad fsize"
    fsize          = fsize.to_i
    _              = sc.scan(/_/)         or raise BAD_STR, "missing _"
    formatted      = sc.peek(fsize)
    begin
      sc.pos   += fsize
    rescue RangeError => ex
      raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
    end
    _              = sc.scan(/_ok$/)      or raise BAD_STR, "bad ok"
    encrypted      = _deformat(format,formatted)
    plaintext      = _decrypt(encryption_key,encrypted,header)
    sp             = StringScanner.new(plaintext)
    r              = sp.scan(/[NCS]/)     or raise BAD_STR, "bad redundancy"
    c              = sp.scan(/[N4ZBM]/)   or raise BAD_STR, "bad compression"
    scheck         = sp.scan(/[a-f0-9]+/) or raise BAD_STR, "bad scheck"
    _              = sp.scan(/_/)         or raise BAD_STR, "missing _"
    compressed     = sp.rest
    redundancy     = CODE_2_REDUNDANCY[r]  || r
    compression    = CODE_2_COMPRESSION[c] || c
    original       = _decompress(compression,compressed)
    scheck_re      = _check(redundancy,original)
    if scheck != scheck_re
      raise(
        CantTouchThisStringError,
        "scheck #{scheck} vs #{scheck_re} in #{sc.string}"
      )
    end
    original
  end

  # How we encode object type.
  #
  TYPE_2_CODE ||= {
    Hash       => 'H',
    Array      => 'A',
    String     => 'S',      # downcased to 's' for string table lookup
    Symbol     => 'Y',      # downcased to 'y' for string table lookup
    Integer    => 'I',
    Float      => 'F',
    NilClass   => 'n',
    TrueClass  => 't',
    FalseClass => 'f',
  }.freeze
  ALL_TYPES   ||= TYPE_2_CODE.keys.freeze

  # How we encode :format and :compression in the OAK strings.
  #
  FORMAT_2_CODE ||= {
    'none'   => 'N',
    'base64' => 'B',  # urlsafe form with padding and whitespace stripped
  }.freeze
  CODE_2_FORMAT ||= FORMAT_2_CODE.invert.freeze

  # How we encode :compression in the OAK strings.
  #
  # Early on, I captures some metrics using the catenation of all our
  # Ruby code as a test file.
  #
  # I measured:
  #
  #   SOURCE 5707334
  #   none   5707370 compression 0.17s decompression 0.16s
  #   lzo    1804765 compression 0.18s decompression 0.16s
  #   lzf    1807971 compression 0.16s decompression 0.17s
  #   lz4    1813574 compression 0.17s decompression 0.14s
  #   zlib   1071216 compression 0.53s decompression 0.19s
  #   bzip2   868595 compression 0.62s decompression 0.33s
  #   lzma    760594 compression 6.22s decompression 0.20s
  #
  # From this, I conclude that only one of lzo,lzf,lz4 is interesting.
  # They all yield approximately the same compression, and their
  # compression times are indistinguishable from the rest of the
  # streaming and encoding times imposed by OAK.
  #
  # I'm settling on supporting only lz4 because it seems to be better
  # supported as a polymorphic lib - it's closer to a defacto standard
  # for the LZ77 family.
  #
  # zlib, bzip2, and lzma each represent interesting distinct choices
  # - I'm keeping support for all three.
  #
  COMPRESSION_2_CODE ||= {
    'none'  => 'N',
    'lz4'   => '4',
    'zlib'  => 'Z',
    'bzip2' => 'B',
    'lzma'  => 'M',
  }.freeze
  CODE_2_COMPRESSION ||= COMPRESSION_2_CODE.invert.freeze

  # How we encode :redundancy in the OAK strings.
  #
  REDUNDANCY_2_CODE ||= {
    'none'  => 'N',
    'crc32' => 'C',
    'sha1'  => 'S',
  }.freeze
  CODE_2_REDUNDANCY ||= REDUNDANCY_2_CODE.invert.freeze

  # Helper method, calculates redundancy check for str.
  #
  def self._check(redundancy,str)
    case redundancy.to_s
    when 'none'        then return '0'
    when 'crc32'       then return '%d' % Zlib.crc32(str)
    when 'sha1'        then return Digest::SHA1.hexdigest(str)
    else
      raise ArgumentError, "unknown redundancy #{redundancy}"
    end
  end

  # Helper method, calculates formatted version of str.
  #
  def self._format(format,str)
    case format.to_s
    when 'none'
      return str
    when 'base64'
      #
      # We actual using "Base 64 Encoding with URL and Filename Safe
      # Alphabet" aka base64url with the option not to use padding,
      # per https://tools.ietf.org/html/rfc4648#section-5.
      #
      # If we were using Ruby 2.3+, we could use the option "padding:
      # false" instead of chopping out the /=*$/ with gsub.
      #
      return Base64.urlsafe_encode64(str).gsub(/=.*$/,'')
    else
      raise ArgumentError, "unknown format #{format}"
    end
  end

  def self._deformat(format,str)
    case format.to_s
    when 'none'
      return str
    when 'base64'
      #
      # Regrettably, Base64.urlsafe_decode64(str) does not reverse
      # Base64.urlsafe_encode64(str).gsub(/=.*$/,''), it raises an
      # ArgumentError "invalid base64".
      #
      # Fortunately, simple Base64.decode64() is liberal in what it
      # accepts, and handles the output of all of encode64,
      # strict_encode64, and urlsafe_encode64 both with and without
      # the /=*$/.
      #
      return Base64.decode64(str.tr('-_','+/'))
    else
      raise ArgumentError, "unknown format #{format}"
    end
  end

  # Helper for wrap() and unwrap(), multiplexes encryption.
  #
  def self._encrypt(encryption_key,data,auth_data,debug_iv)
    return data if !encryption_key
    #
    # WARNING: In at least some versions of OpenSSL::Cipher, setting
    # iv before key would cause the iv to be ignored in aes-*-gcm
    # ciphers!
    #
    #   https://github.com/attr-encrypted/encryptor/pull/22
    #   https://github.com/attr-encrypted/encryptor/blob/master/README.md
    #
    # The issue was reported against version "1.0.1f 6 Jan 2014".  I
    # have yet to figure out whether our current version, 1.1.0, is
    # affected, or when/how the fix will go live.
    #
    # OAK_4 only supports AES-256-GCB.  Although the implementation
    # bug has been fixed and OAK will almost certainly not be used
    # with a buggy version of OpenSSL, nevertheless we take great
    # care to set cipher.key *then* cipher.iv.
    #
    # Still, can't be to careful.
    #
    iv_size          = ENCRYPTION_ALGO_IV_BYTES
    auth_tag_size    = ENCRYPTION_ALGO_AUTH_TAG_BYTES
    if debug_iv && iv_size != debug_iv.size
      raise "unexpected debug_iv.size #{debug_iv.size} not #{iv_size}"
    end
    cipher           = encryption_algo.encrypt
    cipher.key       = encryption_key.key
    iv               = debug_iv || cipher.random_iv
    cipher.iv        = iv
    cipher.auth_data = auth_data
    ciphertext       = cipher.update(data) + cipher.final
    auth_tag         = cipher.auth_tag
    if iv_size != iv.size
      raise "unexpected iv.size #{iv.size} not #{iv_size}"
    end
    if auth_tag_size != auth_tag.size
      raise "unexpected auth_tag.size #{auth_tag.size} not #{auth_tag_size}"
    end
    #
    # Since iv and auth_tag have fixed widths, they are trivial to
    # parse without putting any effort or space into recording their
    # sizes in the message body.
    #
    iv + auth_tag + ciphertext
  end

  # Helper for wrap() and unwrap(), multiplexes decryption.
  #
  def self._decrypt(encryption_key,data,auth_data)
    return data if !encryption_key
    iv_size            = ENCRYPTION_ALGO_IV_BYTES
    auth_tag_size      = ENCRYPTION_ALGO_AUTH_TAG_BYTES
    iv                 = data[0..(iv_size-1)]
    auth_tag           = data[iv_size..(auth_tag_size+iv_size-1)]
    ciphertext         = data[(auth_tag_size+iv_size)..-1]
    cipher             = encryption_algo.decrypt
    cipher.key         = encryption_key.key
    begin
      cipher.iv        = iv
      cipher.auth_tag  = auth_tag
      cipher.auth_data = auth_data
      cipher.update(ciphertext) + cipher.final
    rescue ArgumentError => ex
      #
      # Some of our tests of corrupting OAK strings lead to incorrect
      # parses which cause the data passed to this method to be
      # shorter than ENCRYPTION_ALGO_IV_BYTES.
      #
      # In ruby <= 2.2.7 (w/ openssl 1.1.0), these truncated IVs
      # result in OpenSSL::Cipher::CipherError from cipher.update().
      #
      # In ruby >= 2.4.3 (w/ openssl 2.0.5), truncated IVs result in
      # ArgumentError in cipher.iv=().
      #
      raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
    rescue OpenSSL::Cipher::CipherError => ex
      raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
    end
  end

  # Helper for wrap() and unwrap(), multiplexes compression.
  #
  def self._compress(compression,force,str)
    case compression.to_s
    when 'none'
      compressed  = str
    when 'lz4'
      compressed  = LZ4.compress(str)
    when 'zlib'
      compressed  = Zlib.deflate(str)
    when 'bzip2'
      io          = StringIO.new
      io.set_encoding(Encoding::ASCII_8BIT)
      Bzip2::FFI::Writer.write(io, str)
      compressed  = io.string
    when 'lzma'
      compressed  = LZMA.compress(str)
    else
      raise ArgumentError, "unknown compression #{compression}"
    end
    if !force && compressed.size >= str.size
      compressed  = str
      compression = 'none'
    end
    [compressed,compression.to_s]
  end

  # Helper for wrap() and unwrap(), multiplexes decompression.
  #
  def self._decompress(compression,str)
    case compression.to_s
    when 'none'
      return str
    when 'lz4'
      begin
        return LZ4.uncompress(str)
      rescue LZ4Internal::Error => ex
        raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
      end
    when 'zlib'
      begin
        return Zlib::Inflate.inflate(str)
      rescue Zlib::DataError => ex
        raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
      end
    when 'bzip2'
      io  = StringIO.new(str)
      raw = nil
      begin
        raw = Bzip2::FFI::Reader.read(io)
      rescue Bzip2::FFI::Error::MagicDataError => ex
        raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
      end
      str = raw.b # dupe to Encoding::ASCII_8BIT
      return str
    when 'lzma'
      begin
        raw = LZMA.decompress(str)
      rescue RuntimeError => ex
        raise CantTouchThisStringError, "#{ex.class}: #{ex.message}"
      end
      str = raw.b # dupe to Encoding::ASCII_8BIT
      return str
    else
      raise ArgumentError, "unknown compression #{compression}"
    end
  end

  # Walks obj recursively, touching each reachable child only once
  # without getting caught up cycles or touching DAGy bits twice.
  #
  # Only knows how to recurse into Arrays and Hashs.
  #
  # This traversal is depth-first pre-order with the children of
  # Arrays walked in positional anbd Hash pairs walked in positional
  # order k,v,k,v, etc.
  #
  # @param obj object to walk
  #
  # @param seen Hash which maps object_id => [idx,child] of every
  # object touched, where idx is 0,1,2,... corresponding to the order
  # in which we encountered child.
  #
  # @param reseen List of children which were walked more than once.
  #
  # @param block if present, every object touched is yielded to block
  #
  # @return seen,reseen
  #
  def self._safety_dance(obj,seen=nil,reseen=nil,&block)
    #
    # Note that OAK._serialize() depends on the depth-first pre-order
    # specification here - at least, it assumes that the first element
    # walked will be the first element added to seen.
    #
    seen     ||= {}
    reseen   ||= []
    oid        = obj.object_id
    if seen.has_key?(oid)
      reseen << obj
      return seen,reseen
    end
    seen[oid]  = [seen.size,obj]
    yield obj if block                  # pre-order: this node before children
    if    obj.is_a?(Hash)
      obj.each do |k,v|                 # children in hash order and k,v,...
        _safety_dance(k,seen,reseen,&block)
        _safety_dance(v,seen,reseen,&block)
      end
    elsif obj.is_a?(Array)
      obj.each do |v|                   # children in list order
        _safety_dance(v,seen,reseen,&block)
      end
    end
    return seen,reseen
  end

end
