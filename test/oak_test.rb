# coding: utf-8
require 'test_helper'

class OakTest < Minitest::Test

  KEY_CHAIN_A = OAK::KeyChain.new(
    {
      'a'      => OAK::Key.new('1x3x5x7x9x1x3x5x7x9x1x3x5x7x9x1x'),
      'x'      => OAK::Key.new('12345678901234567890123456789012'),
      'y'      => OAK::Key.new('123456789x123456789x123456789x12'),
      'z'      => OAK::Key.new('123456789x123456789x123456789x12'), # as 'y'
      'l0ng3r' => OAK::Key.new('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
    }
  )
  KEY_CHAIN_B = OAK::KeyChain.new(
    {
      'a'      => OAK::Key.new('1y3y5y7y9y1y3y5y7y9y1y3y5y7y9y1y'),
    }
  )
  DEBUG_IV_A = '1234567890ab'.freeze
  DEBUG_IV_B = 'ba0987654321'.freeze

  # ALL_OPTIONS is constructed to be all combinations of valid
  # options for wrap() or encode().
  #
  # We expect the prime and secondary invariants to hold for all
  # strings under all combos of options.
  #
  # With 2 choices for :format, 3 for :redundancy, 5 for :compression,
  # 2 for :force, there are only 60 ALL_OPTIONS.
  #
  # Still, with some quadraticism, and multiplied by
  # HAPPY_STRINGS.size and HAPPY_OBJECTS.size and 3 or 4 test methods,
  # that's a huge test matrix.
  #
  # To cut down on that quadratic element, we curate also a list of
  # hand-picked INTERESTING_OPTIONS.  Where we compare
  # intraconversions between option sets, we do ALL_OPTIONS *
  # INTERESTING_OPTIONS combos, not ALL_OPTIONS * ALL_OPTIONS.
  #
  OPTION_VALUES = [
    OAK::REDUNDANCY_2_CODE.keys,        # :redundancy
    OAK::COMPRESSION_2_CODE.keys,       # :compression
    [ false, true ],                    # :force
    OAK::FORMAT_2_CODE.keys,            # :format
    [ KEY_CHAIN_A, KEY_CHAIN_B ],       # :key_chain
    [ nil, 'a' ],                       # :key ('a' is a key in both KEY_CHAINS)
    [ nil, DEBUG_IV_A, DEBUG_IV_B ],    # :debug_iv
  ].freeze
  OPTION_NAMES  = [
    :redundancy,
    :compression,
    :force,
    :format,
    :key_chain,
    :key,
    :debug_iv,
  ].freeze
  COMBO_OPTIONS = OPTION_VALUES[0].product(*OPTION_VALUES[1..-1]).freeze
  ALL_OPTIONS   = COMBO_OPTIONS.map{|x|OPTION_NAMES.zip(x).to_h}.freeze
  INTERESTING_OPTIONS = [
    {redundancy: :none,  compression: :none,  force: false, format: :base64},
    {redundancy: :crc32, compression: :none,  force: false, format: :none  },
    {redundancy: :crc32, compression: :lz4,   force: true,  format: :none  },
    {redundancy: :sha1,  compression: :zlib,  force: true,  format: :none  },
    {redundancy: :sha1,  compression: :bzip2, force: true,  format: :none  },
    #
    # With no key, we fall back to OAK_3.
    #
    {key_chain:  KEY_CHAIN_B                                               },
    #
    # Unencrypted OAK_4.
    #
    {key_chain:  KEY_CHAIN_B, force_oak_4: true                            },
    {key_chain:  KEY_CHAIN_B, force_oak_4: true, compression: :none        },
    #
    # Encrypted OAK_4, long key name, fixed IV.
    #
    {key_chain:  KEY_CHAIN_A, key: 'l0ng3r', debug_iv:    DEBUG_IV_A       },
    #
    # Encrypted OAK_4, short key name, random IV.
    #
    {key_chain:  KEY_CHAIN_B, key: 'a'                                     },
  ].freeze

  # CYCLE_A and CYCLE_B are nodes in a cycle A => B, B => A.
  #
  CYCLE_A    = ['cycle_a','TBD']
  CYCLE_B    = ['cycle_b',CYCLE_A].freeze
  CYCLE_A[1] = CYCLE_B                     # cycles impossible without mutation
  CYCLE_A    = CYCLE_A.freeze

  # DAG_A, DAG_B, and DAG_C are nodes in a directed acyclic graph A =>
  # B, A => C, B = C.
  #
  DAG_C      = ['dag_c'].freeze
  DAG_B      = ['dag_b',DAG_C].freeze
  DAG_A      = ['dag_a',DAG_B,DAG_C].freeze

  # DUMMY_HASH and DUMMY_LIST are just bigish multiple-layer trees.
  # B, A => C, B = C.
  #
  DUMMY_HASH    = {'foo'=>123,'bar'=>[1,2,'baz','bang',5]}.freeze
  DUMMY_LIST    = ['foo',123,'bar',1,2,{'baz'=>'bang'},5].freeze

  # UnhappyType can be instantiated, but is known to be a type which
  # is not handled by OAK.
  #
  class UnhappyType
  end

  # HAPPY_OBJECTS are expected to transcode faithfully in OAK under
  # all options.
  #
  HAPPY_OBJECTS = [

    # These "friend of JSON" are objects which JSON would serialize
    # with full reversibility, including object identity graph
    # topology.
    #
    ['Empty String', ''],
    ['Long String', "All work and no play makes jack a dull boy.\n" * 10],
    ['Nil', nil],
    ['False', false],
    ['True', true],
    ['Special String', 'strings'],
    ['Zero', 0],
    ['One', 1],
    ['Negative One', -1],
    ['Big Integer', 1234567890123456789012345678901234567890123456789012345678901234567890],
    ['0.1f', 0.1],
    ['1.23f', 1.23],
    ['-0.34f', -0.34],
    ['Not a Number', Float::NAN],
    ['Negative Not a Number', -Float::NAN],
    ['Infinity', Float::INFINITY],
    ['Negative Infinity', -Float::INFINITY],
    ['Mathematical constant "e"', Math::E],
    ['Mathematical constant "pi"', Math::PI],
    ['Empty Array', []],
    ['Small Array', [1,2,3]],
    ['Mixed type Array', ['one','2','three']],
    ['Empty Hash', {}],
    ['Small Hash', {'a'=>1}],
    ['Interesting Hash', {'a'=>1,'b'=>2,'c'=>[1,2,3]}],
    ['Deeper tree', [nil,{'a'=>1},[1,2,['three','four'],5,6]]],
    ['Non-DAG of 2 strs', ['a','a']],  #
    ['DAG of intern int', [1,1]],
    ['DAG of explicit int', [1] * 2],
    ['DAG of other value types', [true,false,nil,true,false,nil]],

    # An earlier implementation of OAK got into trouble when newlines
    # in object strings were followed by format codes.
    #
    # The idiom:
    #
    #   case "F_\nJ_"
    #   when /^J_/  then do_json()   # hits b/c (/^J_/=~"F_\nJ_") is 3 !!! :(
    #   when /^F_/  then do_frizzy() # miss because secondin order     !!! :(
    #   end
    #
    # Would go down the do_json() path incorrectly when fed a FRIZZY
    # string which contains "\nJ_", which would result in a spurious
    # JSON::ParseError.
    #
    # This object string stresses that woe and similar potential ones,
    # by including lots of OAK format codes in the initial positions
    # of many lines.
    #
    ['Regex Torture Test', (
      "Lots of lines in this string.  Many of them start with one OAK " +
      "format code or another.  This is intended to trip up /^X/ regexps " +
      "which were written thinking that ^ means \"start of string\", not " +
      "\"start of line.\"" +
      "\n" +
      ['','F','F_','J','J_','H','H_','S','S_','SA','SA_'].join("\n") +
      ['','oak_1','oak_1_','oak_2','oak_3','N','B','C','Z','4'].join("\n")
    )],

    # These "friends of YAML" are objects which YAML would serialize
    # with full reversibility, including object identity graph
    # topology, but for which JSON would lose information.
    #
    # Note that in many cases, such as :symbols, YAML can only
    # reversibly transcode some of these objects by virtue of Psyche's
    # Ruby-specific interpretations and use of YAML extension
    # features.  These would not transcode faithfully into another
    # language or another YAML.
    #
    ['The Symbol "symbols"', :symbols],
    ['Array of symbols and strings', ['vs','strings',:strings,'and',':and','symbols',:symbols]],
    ['Hashes w/ non-strings keys', {1=>'a','b'=>2}, {[]=>1,{}=>2}],
    ['DAG of symbols', [:c,:c]],
    ['DAG of hash', [DUMMY_HASH,DUMMY_HASH]],
    ['DAG of list', [DUMMY_LIST,DUMMY_LIST]],
    #
    # Binary strings present special challenges, especially because in
    # Ruby come in different encodings, but on the stream they are
    # always just a train of octets.
    #
    # Some of these are artificial, the latter two are from a
    # challenging UTF-8 sequence which I discovered in the wild as the
    # first 100 bytes of my .git/index which broke an early form which
    # did not sanitize the string encoding at the top of wrap.
    #
    ['UTF_8 String',      ["00112233445566778899AABBCCDDEEFF"*10].pack('H*').force_encoding(Encoding::UTF_8)],
    ['ASCII_8BIT String', ["00112233445566778899AABBCCDDEEFF"*10].pack('H*').force_encoding(Encoding::ASCII_8BIT)],
    ['Another UTF_8 String',      ["FFEEDDCCBBAA99887766554433221100"*10].pack('H*').force_encoding(Encoding::UTF_8)],
    ['Another ASCII_8BIT String', ["FFEEDDCCBBAA99887766554433221100"*10].pack('H*').force_encoding(Encoding::ASCII_8BIT)],
    ['UTF_8 challenging String', [
      '4449524300000002000012a656e827f60000000056e827f60000000001000004' +
      '0048ed8f000081a4000001f600000014000000d8bd422bb27c0e7c6d3639c8ca' +
      'c6ab4bfd851fedbc000b2e6275696c647061636b730000000000000056e9b60d' +
      '00000000'
    ].pack('H*').force_encoding(Encoding::UTF_8)],
    ['ASCII_8BIT challenging String', [
      '4449524300000002000012a656e827f60000000056e827f60000000001000004' +
      '0048ed8f000081a4000001f600000014000000d8bd422bb27c0e7c6d3639c8ca' +
      'c6ab4bfd851fedbc000b2e6275696c647061636b730000000000000056e9b60d' +
      '00000000'
    ].pack('H*').force_encoding(Encoding::ASCII_8BIT)],
    #
    # YAML can handle cycles and DAGs, which was a pleasant surprise.
    #
    ['Cycle', CYCLE_A],
    ['Deep DAG', DAG_A],

    # These "friends of FRIZZY" are objects which FRIZZY serializes
    # with full reversibility, including object identity graph
    # topology, but for which JSON or YAML would lose information.
    #
    # FRIZZY recognizes string identity vs string equivalence.
    #
    ['DAG of one str', ['b'] * 2],

    # These troublesome strings came up when we ramped OAK-for-Summaries.
    #
    # OAK was discarding the encoding, leading to rendering
    # corruption.
    #
    ['Troublesome String',            "@-mentions: @⸨12:345:Some Person⸩"],
    ['Troublesome String UTF_8',      "@-mentions: @⸨12:345:Some Person⸩".force_encoding(Encoding::UTF_8)],
    ['Troublesome String ASCII_8BIT', "@-mentions: @⸨12:345:Some Person⸩".force_encoding(Encoding::ASCII_8BIT)],
  ].freeze

  # UNHAPPY_OBJECTS are friends of nobody, objects which cannot be
  # handled by JSON, YAML, or FRIZZY.  All would be lose information.
  #
  # We expect OAK to reject these objects gracefully.
  #
  UNHAPPY_OBJECTS = [
    UnhappyType,                     # a Class
    UnhappyType.new,                 # not a primitive value type
    [UnhappyType.new],               # array with an unhappy object
    {'x' => UnhappyType.new},        # hash with an unhappy object
    Time.now,                        # a Time object
  ].freeze

  # Non-strings options should all be rejected by decode().
  #
  def test_contract_violations_decode
    [
      nil, {}, [], -1, 0.5, Class, UnhappyType.new
    ].each do |not_a_string|
      assert_raises(ArgumentError,"#{not_a_string}") do
        OAK.decode(not_a_string)
      end
    end
  end

  # Unhappy options should all be rejected by encode().
  #
  def test_contract_violations_encode
    OPTION_NAMES.each do |option_name|
      [ :invalid_symbol, 'invalid_string' ].each do |unhappy_value|
        assert_raises(ArgumentError,"#{option_name} => #{unhappy_value}") do
          OAK.encode('',{ option_name => unhappy_value })
        end
      end
    end
  end

  # Some nasty surprises came up when testing OAK-for-Summaries in
  # prod in Escargot.
  #
  # These are some very direct tests of that woe, which somehow were
  # missed by the seemingly exhaustive tests performed before
  # Escargot.
  #
  def test_cry_about_it
    s = "@-mentions: @⸨12:345:Some Person⸩"
    assert_equal Encoding::UTF_8, s.encoding
    assert_equal s, OAK.decode(OAK.encode(s,serial: :json)),   'json'
    assert_equal s, OAK.decode(OAK.encode(s,serial: :yaml)),   'yaml'
    assert_equal s, OAK.decode(OAK.encode(s,serial: :frizzy)), 'frizzy'
  end

  # The prime invariant: for all objects accepted by encode(),
  # decode() is the inverse of encode() i.e. for all happy obj and all
  # happy opts we expect the identity:
  #
  #   decode(encode(obj,opts))                        == obj
  #
  # Out of extreme paranoia, which mathematically may be redundant, we
  # also test the prime invariant over the domain of outputs of
  # encode() i.e. the identities:
  #
  #   decode(encode(encode(obj,opts),opts_b))         == encode(obj,opts)
  #   decode(decode(encode(encode(obj,opts),opts_b))) == obj
  #
  # Note that encode() is not universal: it does not support
  # user-defined classes and it only supports a few string encodings.
  #
  HAPPY_OBJECTS.each_with_index do |(happy_name, happy_obj),i|
    INTERESTING_OPTIONS.each_with_index do |opts,j|
      define_method "test_decode_vs_encode_#{[i,j,opts,happy_name]}" do
        encode        = OAK.encode(happy_obj,opts)
        #
        # encode() produces recognizable strings.
        #
        assert_equal String,               encode.class
        assert_match(/^oak_[3|4].*_ok$/m,  encode)
        assert_equal Encoding::ASCII_8BIT, encode.encoding
        #
        # In the header comments for lib/util/oak.rb, we promised at
        # least one format which would be free of {}, comma,
        # whitespace, and other nasty characters.
        #
        # That format is :base64.
        #
        # Here, we double-check that all OAK strings using format:
        # :base64 are super-clean - url clean - almost but not
        # always programming language identifier clean.
        #
        if :base64 == opts[:format]
          assert_match(/^oak_[3|4][-_a-zA-Z0-9]*_ok$/, encode)
        end
        #
        # When force=false, we assert that the encoded form is never
        # longer than its uncompressed equivalent.
        #
        if false == opts[:force]
          opts_unc               = opts.dup
          opts_unc[:compression] = :none
          unc                    = OAK.encode(happy_obj,opts_unc)
          assert encode.size <= unc.size
          assert encode.size <  unc.size if encode != unc
        end
        #
        # The prime invariant: decode reverses encode.
        #
        # Note that assert_equiv is harder-core than assert_equal
        # (see implementation of equiv?, below).
        #
        decode = OAK.decode(encode,key_chain: opts[:key_chain])
        assert_equal happy_obj.class,   decode.class
        assert_equiv happy_obj,         decode
        #
        # Nondeterministic if encrypted with no debug_iv, else
        # deterministic.
        #
        encode2       = OAK.encode(happy_obj,opts)
        if !opts[:key] || opts[:debug_iv]
          assert_equal     encode, encode2
        else
          refute_equal     encode, encode2
        end
        #
        # Extreme paranoia: we can reversibly serialize the output
        # of encode().
        #
        # These tests are expensive, but they have revealed bugs where
        # OAK failed to transcode some more complicated OAK strings
        # due to regexp bugs.
        #
        INTERESTING_OPTIONS.each do |opts_b|
          encode2 = OAK.encode(encode,opts_b)
          decode2 = OAK.decode(encode2,key_chain: opts_b[:key_chain])
          assert_equiv encode, decode2, "#{opts_b}"
        end
      end
    end
  end

  # Quick check of the prime invariant for a very simple few cases,
  # against the explosively large ALL_OPTIONS.
  #
  # In this very large and expensive family of tests we are just
  # looking to make sure that OAK.decode() reverses OAK.encode() for
  # at least one datum, mainly to be sure that the manifest type codes
  # do not have any crossed wires.
  #
  # To keep the cost of this test low, we run it only over very, very
  # few inputs.. and we're happy with that.
  #
  def test_all_options_check
    [ 'foo', { 'bar' => ['baz','bang']} ].each_with_index do |obj,i|
      ALL_OPTIONS.each_with_index do |opts,j|
        encode = OAK.encode(obj,opts)
        decode = OAK.decode(encode,key_chain: opts[:key_chain])
        assert_equiv obj, decode, "#{[obj,i,opts,j]}"
      end
    end
  end

  # This test may be redundant with some of the loopy tests elsewhere,
  # but sometimes I need to narrow down on just this one case.
  #
  def test_standalone_frizzy_handles_dag
    opts   = {redundancy: :none, format: :none, compression: :none}
    encode = OAK.encode(DAG_A,opts)
    decode = OAK.decode(encode)
    assert_equiv DAG_A, decode, "DAG encode: #{encode}"
  end

  # This test may be redundant with some of the loopy tests elsewhere,
  # but sometimes I need to narrow down on just this one case.
  #
  def test_standalone_frizzy_handles_cycles
    opts   = {redundancy: :none, format: :none, compression: :none}
    encode = OAK.encode(CYCLE_A,opts)
    decode = OAK.decode(encode)
    assert_equiv CYCLE_A, decode, "cycle encode: #{encode}"
  end

  # The secondary invariant: encode() will reject any objects which it
  # cannot serialize reversibly.
  #
  def test_unhappy_objects
    UNHAPPY_OBJECTS.each_with_index do |unhappy_obj,i|
      assert_raises(OAK::CantTouchThisObjectError,"#{[i,unhappy_obj]}") do
        OAK.encode(unhappy_obj)
      end
    end
  end

  # OAK._safety_dance is part of the private implementation of OAK,
  # but so much hinges on it that I am giving it special test
  # coverage.
  #
  [
    [
      123,
      [[0,123]],
      [],
    ],
    [
      [123],
      [[0,[123]],[1,123]],
      [],
    ],
    [
      [12,3],
      [[0,[12,3]],[1,12],[2,3]],
      [],
    ],
    [
      [1,2,3,[1,2],1],
      [[0,[1,2,3,[1,2],1]],[1,1],[2,2],[3,3],[4,[1,2]]],
      [1,2,1],
    ],
    [
      ['b','b'],                          # two strings with the same value
      [[0,['b','b']],[1,'b'],[2,'b']],
      [],
    ],
    [
      ['b']*2,                            # one string two times
      [[0,['b','b']],[1,'b']],
      ['b'],
    ],
    [
      DAG_A,
      [[0,DAG_A],[1,'dag_a'],[2,DAG_B],[3,'dag_b'],[4,DAG_C],[5,'dag_c']],
      [DAG_C],
    ],
    [
      CYCLE_A,
      [[0,CYCLE_A],[1,'cycle_a'],[2,CYCLE_B],[3,'cycle_b']],
      [CYCLE_A],
    ],
  ].each_with_index do |(obj,expected_values,expected_reseen),idx|
    define_method "test_safety_dance_for_#{idx}" do
      #
      # The keys of the output of OAK._safety_dance() are object_ids.
      #
      # Thus, they are nondeterministic, and to keep this test simple
      # we check only seen.keys.first.
      #
      # The values and their ordering are all deterministic, so we check
      # all of seen.values.
      #
      seen,reseen = OAK._safety_dance(obj)
      assert_equal obj.object_id,   seen.keys.first, obj
      assert_equal expected_values, seen.values,     obj
      assert_equal expected_reseen, reseen,          obj
    end
  end

  # Checks that a and b are structurally equivalent.  This is the main
  # criteria to recognize successful reconstitution of an object after
  # serialization and deserialization.
  #
  # This means they are ==, but also some additional requirements:
  #
  #   - hash keys order is preserved
  #   - have same graph i.e. are hierarchical or daggy or cyclic together
  #
  # saw_a and saw_b are used to keep track of what objects we have
  # already walked - and in what order.
  #
  def equiv?(a,b,saw_a=Hash.new,saw_b=Hash.new)
    a_oid        = a.object_id
    b_oid        = b.object_id
    return saw_a[a_oid] == saw_b[b_oid]         if saw_a[a_oid] || saw_b[b_oid]
    saw_a[a_oid] = saw_a.size
    saw_b[b_oid] = saw_b.size
    return true                                 if a_oid        == b_oid
    return true                                 if a_oid        == b_oid
    return false                                if a.class      != b.class
    if    a.is_a?(Hash)
      return false if a.size != b.size
      return false if   !equiv?( a.keys,   b.keys,   saw_a, saw_b)
      return false if   !equiv?( a.values, b.values, saw_a, saw_b)
      return true
    elsif a.is_a?(Array)
      return false if a.size != b.size
      a.each_with_index.each do |child,index|
        return false if !equiv?( child,    b[index],  saw_a, saw_b)
      end
      return true
    elsif a.is_a?(String)
      #
      # OAK preserves String.encoding.
      #
      return (a == b) && (a.encoding == b.encoding) && (a.bytes == b.bytes)
    elsif a.is_a?(Symbol)
      return a == b
    elsif nil == a || false == a || true == a
      return a == b
    elsif a.is_a?(Integer)
      return a == b
    elsif a.is_a?(Float)
      #
      # Horrifyingly, Float::NAN != Float::NAN.
      #
      # However, for our purposes all NAN are equivalent.
      #
      return (a.nan? || b.nan?) ? (a.nan? == b.nan?) : (a == b)
    end
    raise ArgumentError, "not handled: #{a} #{b}"
  end
  # Like assert_equal() but uses equiv? instead of ==.
  #
  def assert_equiv(a,b,msg=nil)
    return if equiv?(a,b)
    if msg
      flunk "#{msg}.\n<#{a}> expected but was\n<#{b}>."
    else
      flunk "<#{a}> expected but was\n<#{b}>."
    end
  end

  def test_equiv?
    x = 'x' # a conveniently reusable, re-referencable object
    [
      [ nil,             nil                   ], # one single object_id
      [ 1,               1                     ], # one single object_id
      [ [],              []                    ], # trivially equivalent
      [ {},              {}                    ], # trivially equivalent
      [ '',              ''                    ], # trivially equivalent
      [ 'a',             'a'                   ], # two different object_ids
      [ x,                x                    ], # one single object_ids
      [ ['a','a'],       ['a','a']             ], # each pair is 2 objects
      [ [x,x],           [x,x]                 ], # each pair is 1 object twice
      [ DAG_A,           DAG_A                 ], # DAG with itself
      [ DAG_A,           ['dag_a',DAG_B,DAG_C] ], # DAG with same shape
      [ {1=>2,3=>4},     {1=>2,3=>4}           ], # hash w/ same key order
      [ {'a'=>2,'b'=>4}, {'a'=>2,'b'=>4}       ], # hash w/ same key order
      [ Float::INFINITY, Float::INFINITY       ],
      [ Float::NAN,      Float::NAN            ],
      [ Float::NAN,      -Float::NAN           ],
    ].each do |a,b|
      assert_equal true, equiv?(a,b), "comparing #{a} to #{b}"
      assert_equal true, equiv?(b,a), "comparing #{a} to #{b} backwards"
      assert_equiv a,    b
      assert_equiv b,    a
    end
    [
      [ nil,     1                                          ], # not ==
      [ 1,       ''                                         ], # not ==
      [ 1,       2                                          ], # not ==
      [ {1=>2,3=>4}, {3=>4,1=>2}                            ], # hash key order
      [ [x,x],   ['x','x']                                  ], # 1 vs 2 oids
      [ ['a']*2, ['a','a']                                  ], # 1 vs 2 oids
      [ DAG_A,   ["dag_a", ["dag_b", ["dag_c"]], ["dag_c"]] ], # dag vs hiar
      [ Float::INFINITY, -Float::INFINITY                   ],
    ].each do |a,b|
      assert_equal false, equiv?(a,b), "comparing #{a} to #{b}"
      assert_equal false, equiv?(b,a), "comparing #{a} to #{b} backwards"
    end
    #
    # Every object we can conceive of should be equiv? to itself.
    # Except Float::NAN, which is not equal to itself!
    #
    (HAPPY_OBJECTS.map(&:last) + UNHAPPY_OBJECTS).each do |a|
      assert_equal true, equiv?(a,a),     a
      assert_equal true, equiv?([a],[a]), [a]
    end
    #
    # equiv? is halting, recognizes both equivalent and non-equivalent
    # cyclic graphs.
    #
    assert_equal true,  equiv?(CYCLE_A,CYCLE_A)
    assert_equal true,  equiv?(CYCLE_B,CYCLE_B)
    assert_equal false, equiv?(CYCLE_A,CYCLE_B)
    assert_equal false, equiv?(CYCLE_B,CYCLE_A)
    long_cycle          = ['cycle_a','TBD']
    long_cycle[1]       = ['cycle_b','TBD']
    long_cycle[1][1]    = ['cycle_c','TBD']
    long_cycle[1][1][1] = long_cycle
    assert_equal true,  equiv?(long_cycle,long_cycle)
    assert_equal false, equiv?(CYCLE_A,long_cycle)
    assert_equal false, equiv?(long_cycle,CYCLE_A)
  end

  # OAK is an archive format, so we need to know that output which it
  # produced in the past remains decodable in the future - even if
  # those are strings which the encoder no longer generates!
  #
  # Here, we verify that a snapshot of encoded strings decode to a few
  # dedicated sources.
  #
  {
    #
    # Lots of OAK literals are more than 80 characters.
    #
    [1, 2, 3] => [
      'oak_3NNN_0_16_F4A3_1_2_3I1I2I3_ok',
      'oak_3N4B_0_26_EPABRjRBM18xXzJfM0kxSTJJMw_ok',
      'oak_3CZB_2690303115_32_eJxzM3E0jjeMN4o39jT0NPI0BgAjLwQT_ok',
      'oak_3CBB_2690303115_67_QlpoOTFBWSZTWcHMhhYAAASOADwAISAAAKAAIhkNqEMCIJJQCoNvxdyRThQkMHMhhYA_ok',
      'oak_3SMB_93d431eee5bda8c932415ff77c6dbeff5bf09327_46_XQAAgAAQAAAAAAAAAAAjDQQjWUQtVGJnd4Z_40qnoHiC-w_ok',
      'oak_4_N29_CN2690303115_F4A3_1_2_3I1I2I3_ok',
      'oak_4_B39_Q04yNjkwMzAzMTE1X0Y0QTNfMV8yXzNJMUkySTM_ok',
      'oak_4l0ng3r_B76_z3addGUu282MCm6w0KxfW17tyZRH4RZcr4esDoNbBgFZwhdcXLw2tItgdwAJSUk99hJDrRUeczpl_ok',
    ],
    {:foo=>"foo", "foo"=>["x"]*10} => [
      'oak_3NNN_0_53_F6H2_1_2_3_4YA3_foosU0sU0A10_5_5_5_5_5_5_5_5_5_5SU1_x_ok',
      'oak_3N4B_0_55_Nf4PRjZIMl8xXzJfM180WUEzX2Zvb3NVMHNVMEExMF81AgBQU1UxX3g_ok',
      'oak_3CZB_3325243002_58_eJxzM_MwijeMN4o3jjeJdDSOT8vPLw41ACJHQ4N4U0wYHGoYXwEAo0QPtw_ok',
      'oak_3CBB_3325243002_100_QlpoOTFBWSZTWQi_UFsAAAwPgH8AIUAKIIEAiEAgADFNMjExMQaCNBpppo6HmEdApkQdoqIoTPenLEBtLc9VzX4u5IpwoSARfqC2_ok',
      'oak_3SMB_e051b00771486ba00daf2965684cc433e3130f54_72_XQAAgAA1AAAAAAAAAAAjDYUDRzA1VkFtcJTZl6jF84uVU7kx3HrdEnxZ-punCZGsIspruigA_ok',
      'oak_4_N66_CN3325243002_F6H2_1_2_3_4YA3_foosU0sU0A10_5_5_5_5_5_5_5_5_5_5SU1_x_ok',
      'oak_4_B88_Q04zMzI1MjQzMDAyX0Y2SDJfMV8yXzNfNFlBM19mb29zVTBzVTBBMTBfNV81XzVfNV81XzVfNV81XzVfNVNVMV94_ok',
      'oak_4l0ng3r_B126_vKI7U16Bs77hKALnx182TmARJqZEhcdxSDQMd8PILqMADbmIqCT50yfJqa0PtCHzg2GK7dFFUa74SSX9LL9VAgw09VqHJLiptAyghyelZ11DdWHVp41ruFgn7ltRww_ok',
    ],
    -1 => [
      'oak_3NNN_0_5_F1I-1_ok',
      'oak_3N4B_0_10_BVBGMUktMQ_ok',
      'oak_3CZB_1471752618_18_eJxzM_TUNQQAA40BHw_ok',
      'oak_3CBB_1471752618_59_QlpoOTFBWSZTWVlI9hgAAAGcAAACIAABICAAIZpoM00RZxdyRThQkFlI9hg_ok',
      'oak_3SMB_43b02206a74a67b297013390f3a9a9219b1f7962_31_XQAAgAAFAAAAAAAAAAAjDEUi7iPNwAA_ok',
      'oak_4_N18_CN1471752618_F1I-1_ok',
      'oak_4_B24_Q04xNDcxNzUyNjE4X0YxSS0x_ok',
      'oak_4l0ng3r_B62_aJjPBsb6RehJ2WqxBWukIj1OoWs5FPQo8aPA4Qb_V5_LYrWxv9xhwY8YN2_x6A_ok',
    ],
    Float::NAN => [
      'oak_3NNN_0_6_F1FNaN_ok',
      'oak_3N4B_0_11_BmBGMUZOYU4_ok',
      'oak_3CZB_3715844286_19_eJxzM3TzS_QDAAWxAbs_ok',
      'oak_3CBB_3715844286_59_QlpoOTFBWSZTWVB_BqkAAACNACAAAQEgACAAIYyDNNMCvF3JFOFCQUH8GqQ_ok',
      'oak_3SMB_d8c13d0be2a3a5f610edb377da4775b06849aa8c_32_XQAAgAAGAAAAAAAAAAAjDETFJCIvH0AA_ok',
      'oak_4_N19_CN3715844286_F1FNaN_ok',
      'oak_4_B26_Q04zNzE1ODQ0Mjg2X0YxRk5hTg_ok',
      'oak_4l0ng3r_B63_rTa1YgKXpq0AClJPmBJFDjTXmaPUCFnyqsHXob2ksFaysVf0JtP1i8qOYVWG5Vs_ok',
    ],
    nil => [
      'oak_3NNN_0_3_F1n_ok',
      'oak_3N4B_0_7_AzBGMW4_ok',
      'oak_3CZB_3875627917_15_eJxzM8wDAAGlAOY_ok',
      'oak_3CBB_3875627917_56_QlpoOTFBWSZTWUijQlkAAACNACAAAQAAASAAIZgZgWF3JFOFCQSKNCWQ_ok',
      'oak_3SMB_888d15ad4ab5fe16c9bf6b2fa27307f3566df967_28_XQAAgAADAAAAAAAAAAAjDEnAAAAA_ok',
      'oak_4_N16_CN3875627917_F1n_ok',
      'oak_4_B22_Q04zODc1NjI3OTE3X0Yxbg_ok',
      'oak_4l0ng3r_B59_1JUdYj3nnj4BGjsEfw-tAEaU_So8DVcIJIbQELZ_JVb5hP0HQd5x-qMJU-Q_ok',
    ],
  }.each do |obj,oaks|
    oaks.each do |oak|
      define_method "test_oak_remembers_its_commitment_to_#{oak}" do
        assert_equiv obj, OAK.decode(oak, key_chain: KEY_CHAIN_A)
      end
    end
  end

  # On Tuesday 2016-06-27 at 15:25 we set
  # SUMMARY_ACCESSOR_READ_FROM_HASH=false, thus making the OAK form of
  # the Summary cache authoritative.
  #
  # It ran without issues for two days until Thursday 2016-06-30 at
  # 15:17, when a single recurring dead letter cropped up.
  #
  # It proved to be a failure in OAK.decode().
  #
  # This test repros that failure, with the precise data in question.
  #
  def test_thursday_2016_06_30_decode_failure
    #
    # Lots of OAK literals are more than 80 characters.
    #
    oak = 'oak_3SBB_99283e99d2338e8e956c60caa8b72258ad68c933_1679_QlpoOTFBWSZTWVjZkAUAAhkfgEALf_A14QoAv-_f8FAFp7tAK3nHhG566BXUNNENASabSNU9QaMhmo0GgingYqo0ABoaAAAA0xIAhU9QaA0AAABIkmTRqJoA9NRoPUNDQDCREFNoTUeiT01BoNAA09S8fD7ff0_Kt695CUoQgmwG_Ox5A5_HhyGdwq-PAVinUMwYXNMLZewT5kVMyZC3alFpHV4wd7uBeKWCBj46JwhTBLYPKgizoEVkR1iKAVgXEeTVTcVQgWlONiziPXf1O1oq2WIpAw5UkoXMsfEoL3MfptHXWkNoRETgie0DZkAw6xAqFJILnQNhpWbYGRlzMBYikuY8Sfg1WZrOgyBS5GZ4rWbzOrT0uRzmDtuL45xc0QSyVzASqlhwGydwNNkk0Wt84yqYyubiZzO882N4CIJRFSSe1NQJnuSykYJ0VxASulsV4nd9uvVKW4xXhQLY5zHWqaaNZxW5M64mZSSSxAbaRJO0sAJ0WL2xOaVrxa2eNa43okGQr3kYBphKOzbgIGEELJdJPCb2E7kaZgJPJHFd01ilJdLc85e92i-iUSqVs08qgBsZOoBgYNiJtatFdzaNpTlKdL0tUUuoCpmwqKuyBkKYOhFjRAUB06jF-KbXVK9bWtYxfPG6EEEulWMIXJM5REFHRmg7wjFqA8EVaMO7JYcGBNYMNF2sWsYWoY7FOkqlbBJ1nTNLRmiEDS1sgBNDGhNLEM7ZSOF9rrWgpuvN9IwRjdsBk62ndGMjT28fJ15dHJxwcMHYKPp0WRhLSPHlGSUVdt8ttxJsLOe_SXseazjiLtzbBTqUHKbZgyECW7OOPcANiEJRE3tIYbF7WkBktKPRusUkSZu7u8qEKzRekZyehlwiTRIMpJKr0xSGcAHGOjZmO-ZAxQkpQGODJJJN1TDLaBDXcLIQZjQATyWpwyFrIGSLzRgq0VWDbB4aA6rRLGlw8FzFO5m7d7lCqlIqAi0QLjHgc2VW1JLb74G233_dL4y2jO_NOAdbjhEFaWpzeScwjkDsNdpU2OVg2tKFU0ysNM1F821ltyrHFhUcmjCANIVKVNNoQCx1Zm0i6Xno7yoRJ8jAIdmq19dPURqTMQ7xkGKcHVKCBQYcNW_9CEKYsA20DlYfXo7ASSNQdoeV8Jpk8Zbt2D09DEBi49gkGkR5mkDGCgoMbghLkW0YXqHcWvwKBrfIJQpssnxio7lmf6XXiPcZCHayU2DRFoOWEOlJFCiKawMtzpxOxwFVE0cj1J2DL_TJyMsZKR9ttHcSX0CFNMeY1kN4qOFVKgzA6wyhg1_MHqO8AY4ME6WDkGaql3sLBxLLARuFbgchV_JgoXpYLIUneT7QwTXWjjwBlyoUOdTnm8xjzDmsU8a0kIOGd8qBkqlrhBAHqiqFIrwKbeeLUBeF0KQ6pGKkHVRQoPAOcxwFCQvXINN9TuHjbuLnK2oKE4yzR7uG3QsLS-EjbxG7JDCD4G5otwZukMRvNDcaIDUnFs2rhRUAIq6T_3vlrDIoK1WigokB5-nb0FOXwpHv3704mNWlaUVRoqh1pqjjx2EdH5FAleA7Aqi4NvkSLmHQcJqZiSjKoqk6SA0YXBZpsVaQ1RK8nlUljTpUmtzUYqBKCp7ApTUXZ1XAYF2SBYEjXm23Vwk0MZIOIu5IpwoSCxsyAKA_ok'
    OAK.decode(oak)
  end

  # Digging deeper into the Thursday 2016-06-30 issue showed a problem
  # recognizing Floats which had been encoded with scientific
  # notation.
  #
  # We dig down into that specific issue here, going deep enough to
  # construct artificial OAK string, some of which would not even be
  # generated by OAK.encode() because they involve floating point
  # representations which round to 0 in Ruby.
  #
  {
    '8.44529598297266e+19' => 8.44529598297266e+19, # problem from 2016-06-30
    '-6'                   => -6.0,
    '6'                    => 6.0,
    '-6.'                  => -6.0,
    '6.'                   => 6.0,
    '-6.0'                 => -6.0,
    '6.0'                  => 6.0,
    '-6.0e'                => -6.0,
    '6.0e'                 => 6.0,
    '-6.0e+'               => -6.0,
    '6.0e+'                => 6.0,
    '-6.0e+0'              => -6.0,
    '6.0e+0'               => 6.0,
    '-6.0e+2'              => -6.0e+2,
    '6.0e+2'               => 6.0e+2,
    '-6.0e+10'             => -6.0e+10,
    '6.0e+10'              => 6.0e+10,
    '-6.0e+100'            => -6.0e+100,
    '6.0e+100'             => 6.0e+100,
    '-6.0e+1000'           => -Float::INFINITY,
    '6.0e+1000'            => Float::INFINITY,
    '-6.0e-'               => -6.0,
    '6.0e-'                => 6.0,
    '-6.0e-0'              => -6.0e-0,
    '6.0e-0'               => 6.0e-0,
    '-6.0e-2'              => -6.0e-2,
    '6.0e-2'               => 6.0e-2,
    '-6.0e-10'             => -6.0e-10,
    '6.0e-10'              => 6.0e-10,
    '-6.0e-100'            => -6.0e-100,
    '6.0e-100'             => 6.0e-100,
    '-6.0e-1000'           => -0.0,
    '6.0e-1000'            => 0.0,
    '-0.0'                 => -0.0,
    '0.0'                  => 0.0,
    '1234'                 => 1234.0,
    '-1234'                => -1234.0,
    '0123'                 => 123.0,
    '-0123'                => -123.0,
  }.each do |str,float|
    define_method "test_thursday_2016_06_30_extreme_#{str}_#{float}" do
      oak_s = "oak_3NNN_0_#{2+str.size}_F1F#{str}_ok" # size too small
      oak_b = "oak_3NNN_0_#{4+str.size}_F1F#{str}_ok" # size too big
      oak   = "oak_3NNN_0_#{3+str.size}_F1F#{str}_ok" # size just right
      assert_raises(OAK::CantTouchThisStringError) do
        OAK.decode(oak_s)
      end
      assert_raises(OAK::CantTouchThisStringError) do
        OAK.decode(oak_b)
      end
      assert_equal float, OAK.decode(oak), "#{str} ==> #{oak}"
    end
  end

  def testencryption_algo_is_new_each_time_to_prevent_state_bleed
    refute_equal OAK.encryption_algo.object_id, OAK.encryption_algo.object_id
  end

  def test_random_key_and_random_iv_are_very_random
    #
    # OAK.random_key and OAK.random_iv expected to approach
    # cryptographical security.
    #
    # Thus, it is a small thing to ask that collisions reliably do not
    # happen even among a draw of 1000s of these.
    #
    keys = Array.new(1000) { OAK.random_key }
    assert_equal keys,       keys.uniq
    assert_equal [ String ], keys.map(&:class).uniq
    assert_equal [ 32     ], keys.map(&:size).uniq # AES-256     256-bit keys
    ivs  = Array.new(1000) { OAK.random_iv  }
    assert_equal ivs,  ivs.uniq
    assert_equal [ String ], ivs.map(&:class).uniq
    assert_equal [ 12     ], ivs.map(&:size).uniq  # AES-256-GCM  96-bit ivs
  end

  def test_key_inspect_is_printable
    k    = OAK.random_key
    key  = OAK::Key.new(k)
    ["#{key}", "#{[key]}"] # literals in void context test for crash
  end

  def test_key_inspect_obfuscates_the_sensitive_key
    k    = OAK.random_key
    key  = OAK::Key.new(k)
    assert_equal    k,           key.key
    refute_includes key.inspect, key.key
    refute_includes key.inspect, key.key.inspect
    refute_includes key.to_s,    key.key
    refute_includes "#{key}",    key.key
    refute_includes "#{key}",    key.key.inspect
    refute_includes "#{[key]}",  key.key
    refute_includes "#{[key]}",  key.key.inspect
  end

  def test_key_initialize_demands_valid_values
    #
    # unhappy some are non-strings or empty or will offend OpenSSL::Cipher
    #
    key = OAK.random_key
    OAK::Key.new(key)                               # random preferred like so
    OAK::Key.new('x' + key[1..-1])                  # any bytes are fine
    assert_raises(ArgumentError) do                 # non-string
      OAK::Key.new(nil)
    end
    assert_raises(ArgumentError) do                 # non-string
      OAK::Key.new(1)
    end
    assert_raises(ArgumentError) do                 # way too short
      OAK::Key.new('')
    end
    assert_raises(ArgumentError) do                 # 1 byte too small
      OAK::Key.new(key[1..-1])
    end
    assert_raises(ArgumentError) do                 # 1 byte too long
      OAK::Key.new(key + 'x')
    end
  end

  def test_keychain_initialize_demands_valid_values
    k1   = OAK.random_key
    k2   = OAK.random_key
    key1 = OAK::Key.new(k1)
    key2 = OAK::Key.new(k2)
    #
    # unhappy key_chains
    #
    assert_raises(ArgumentError) do
      OAK::KeyChain.new(nil)                           # non-Hash
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, 2   => key2 })  # non-String key
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, 'x' => 'bad' }) # non-Key value
    end
    #
    # happy key_chains
    #
    OAK::KeyChain.new({})
    OAK::KeyChain.new({ 'a' => key1 })
    OAK::KeyChain.new({ 'a' => key1, 'b' => key2 })
    #
    # OAK._wrap() and OAK._unwrap() are simplistic about how they
    # represent key names in OAK strings.
    #
    # To support this, only ASCII alphanumeric names are allowed as
    # key names.
    #
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, '_'   => key2 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, '_x'  => key2 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, 'x_'  => key2 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a' => key1, 'x_x' => key2 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ '0' => key1 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ '-' => key1 })
    end
    OAK::KeyChain.new(  { 'a2c' => key1 }) # identifier-like alphanumerics OK
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ '2ac' => key1 }) # number-first alphanumerics bad
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a.c' => key1 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ 'a!c' => key1 })
    end
    assert_raises(ArgumentError) do
      OAK::KeyChain.new({ '' => key1 })
    end
  end

  def test_keychain_is_to_s_and_inspectable
    k1    = OAK.random_key
    k2    = OAK.random_key
    key1  = OAK::Key.new(k1)
    key2  = OAK::Key.new(k2)
    chain = OAK::KeyChain.new({ 'a' => key1, 'b' => key2 })
    chain.to_s
    chain.inspect
    ["#{chain}", "#{[chain]}"] # literals in void context test for crash
  end

  def test_parse_env_chain
    key_a  = OAK.random_key
    key_b  = OAK.random_key
    env    = {
      'FOO_KEYS'    => 'a  ,,, b    ',
      'FOO_KEY_a'   => OAK.encode(key_a),
      'FOO_KEY_b'   => OAK.encode(key_b),
    }
    key_chain = OAK.parse_env_chain(env,'FOO')
    assert_kind_of OAK::KeyChain, key_chain
    assert_equal   ['a','b'],     key_chain.keys.keys
    assert_equal   key_a,         key_chain.keys['a'].key
    assert_equal   key_b,         key_chain.keys['b'].key
    env['FOO_KEY_b'] = OAK.encode(key_b[0..-2])     # reduce length by 1 byte
    assert_raises(ArgumentError) do
      OAK.parse_env_chain(env,'FOO')
    end
    env['FOO_KEY_b'] = OAK.encode(key_b + 'x')      # extend length by 1 byte
    assert_raises(ArgumentError) do
      OAK.parse_env_chain(env,'FOO')
    end
  end

  def test_oak_4_hello_world
    #
    # Life is much simpler without encryption.
    #
    plaintext    = 'Hello, World!'
    oak_3_expect = 'oak_3CNB_2351984628_27_RjFTVTEzX0hlbGxvLCBXb3JsZCE_ok'
    oak_3_actual = OAK.encode(plaintext)
    assert_equal oak_3_expect, oak_3_actual
    #
    # We need a lot more machinery even for the simplest encryption.
    #
    key_name     = 'x'
    key_chain    = OAK::KeyChain.new(
      {
        key_name => OAK::Key.new('12345678901234567890123456789012'),
      }
    )
    oak_4_expect = 'oak_4x_B82_MTIzNDU2Nzg5MGFiMEfhQUC16K5VhOBTymoYFR03KbElBXBUR9UYsVEXOPXFNDkq7m_F8NM2cSxOniERUg_ok'
    oak_4_actual = OAK.encode(
      plaintext,
      key_chain: key_chain,
      key:       key_name,
      debug_iv:  '1234567890ab',
    )
    assert_equal oak_4_expect, oak_4_actual
    #
    # OAK_4 is just as reversible as OAK_3.
    #
    assert_equal plaintext,    OAK.decode(oak_3_actual)
    assert_equal plaintext,    OAK.decode(oak_4_actual,key_chain: key_chain)
    #
    # OAK_4 is not decodable without the key_chain:
    #
    assert_raises(OAK::CantTouchThisStringError) do
      OAK.decode(oak_4_actual)
    end
    #
    # As the IV changes, the OAK_4 encryption changes - but remains
    # reversible.
    #
    oak_4_expect = 'oak_4x_B82_MXgzeDV4N3g5MGFi82HmvjWx3e5g_29JHzKppGvc5h08fQC8qmAZLwnwYtiehPzqsZnOR1cZQceXSPyKnQ_ok'
    oak_4_actual = OAK.encode(
      plaintext,
      key_chain: key_chain,
      key:       key_name,
      debug_iv:  '1x3x5x7x90ab',
    )
    assert_equal oak_4_expect, oak_4_actual
    assert_equal plaintext,    OAK.decode(oak_4_actual,key_chain: key_chain)
    #
    # With no debug_iv specified, OAK_4 uses a different IV each time.
    #
    free_actual  = Array.new(1000) do
      OAK.encode(
        plaintext,
        key_chain: key_chain,
        key:       key_name,
      )
    end
    assert_equal free_actual,   free_actual.uniq
    #
    # ...but they are all reversible.
    #
    free_reverse = free_actual.map { |f| OAK.decode(f,key_chain: key_chain) }
    assert_equal [ plaintext ], free_reverse.uniq
  end

  def test_properties_of_encrypted_oak_strings
    key_chain = OAK::KeyChain.new(
      {
        'x' => OAK::Key.new('12345678901234567890123456789012'),
        'y' => OAK::Key.new('123456789x123456789x123456789x12'),
        'z' => OAK::Key.new('123456789x123456789x123456789x12'), # as 'y' above
      }
    )
    #
    # Without encryption, note "oak_3".
    #
    # Note also that even as compression changes, the redundancy chunk
    # stays constant as "2640238464".
    #
    expect = 'oak_3CNB_2640238464_16_RjFTVTZfSGVsbG8h_ok'
    got    = OAK.encode('Hello!')
    assert_equal expect, got
    expect = 'oak_3CMB_2640238464_40_XQAAgAAMAAAAAAAAAAAjDEZlkoKYZGUrRpu2JogA_ok'
    got    = OAK.encode(
      'Hello!',
      compression: :lzma,
      force:       true,
    )
    assert_equal expect, got
    expect = 'oak_3CZB_2640238464_27_eJxzMwwONYv3SM3JyVcEABePA8o_ok'
    got    = OAK.encode(
      'Hello!',
      compression: :zlib,
      force:       true,
    )
    assert_equal expect, got
    #
    # Including a key_chain but not a key results in no encryption -
    # it is the same as if no key_chain were passed.
    #
    assert_equal OAK.encode('Hi!'), OAK.encode('Hi!',key_chain: key_chain)
    #
    # With encryption, note "oak_4y_" indicating the string was
    # encrypted with key 'y'.
    #
    # Note also that, encrypted, the plaintext headers include only
    # 'oak_4y_B71' which indicates:
    #
    #   OAK version 4, encryption key 'y', 71 bytes of base64 content
    #
    # All other information is hidden away.
    #
    expect = 'oak_4y_B71_MTIzNDU2Nzg5MGFiuHMLh8whh6KjGn5DUEiEg6aODYnDQoLbFmyc302I_SdHzQvqIfmgrxs_ok'
    got    = OAK.encode(
      'Hello!',
      key_chain: key_chain,
      key:       'y',
      debug_iv:  '1234567890ab',
    )
    assert_equal expect, got
    expect = 'oak_4y_B82_MTIzNDU2Nzg5MGFi4uo_bg71otWPRdHezwh62qaaDYnDQoLbFmyc3022UAch91qXz2KEDfNOPnDZjTSPVQ_ok'
    got    = OAK.encode(
      'Hello!',
      key_chain:   key_chain,
      key:         'y',
      compression: :zlib,
      force:       true,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    expect = "oak_4y_N61_1234567890abH\xBA\xECL\xE7fa\x1F9Vf\xFB\xD3+O\xBB\xA6\x9A\r\x89\xC3B\x82\xDB\x16l\x9C\xDFM\xB6P\a!\xF7Z\x97\xCFb\x84\r\xF3N>p\xD9\x8D4\x8FU_ok".force_encoding(Encoding::ASCII_8BIT)
    got    = OAK.encode(
      'Hello!',
      key_chain:   key_chain,
      key:         'y',
      format:      :none,
      compression: :zlib,
      force:       true,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    #
    # The footprint of the key name is minimal, but authentication
    # includes the key name so using the same key+iv with 2 different
    # names still leads to 2 distinct encodings.
    #
    got_y   = OAK.encode(
      'Hello!',
      key_chain: key_chain,
      key:       'y',
      debug_iv:  '1234567890ab',
    )
    got_z   = OAK.encode(
      'Hello!',
      key_chain: key_chain,
      key:       'z',
      debug_iv:  '1234567890ab',
    )
    expect_y = 'oak_4y_B71_MTIzNDU2Nzg5MGFiuHMLh8whh6KjGn5DUEiEg6aODYnDQoLbFmyc302I_SdHzQvqIfmgrxs_ok'
    expect_z = 'oak_4z_B71_MTIzNDU2Nzg5MGFiU342iM2a5ZMbsfbJIw6ww6aODYnDQoLbFmyc302I_SdHzQvqIfmgrxs_ok'
    assert_equal key_chain.keys['y'].key, key_chain.keys['z'].key
    assert_equal expect_y,                got_y
    assert_equal expect_z,                got_z
    #
    # When IVs are not specified, they are random.  Encrypted OAK
    # strings are nondeterministic with extraordinarily low chance of
    # collision.
    #
    oaks = Array.new(1000) { OAK.encode('Hi!',key_chain: key_chain,key: 'z') }
    assert_equal oaks, oaks.uniq
  end

  def test_reversibility_of_encrypted_oak_strings
    plain     = 'Hello!'
    key_chain = OAK::KeyChain.new(
      {
        'a' => OAK::Key.new('12345678901234567890123456789012'),
      }
    )
    expect    = 'oak_3CNB_2640238464_16_RjFTVTZfSGVsbG8h_ok'
    got       = OAK.encode(plain)
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
    expect    = 'oak_4a_B71_MTIzNDU2Nzg5MGFikCNVKE_dzZGqOFk7akDB8R03KbQkBHtfS9ccvVEXOPXFM1U9w2bF850_ok'
    got       = OAK.encode(
      plain,
      key_chain:   key_chain,
      key:         'a',
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
    expect    = 'oak_4a_B59_MTIzNDU2Nzg5MGFi04uuu8jmzJbGZpXg9BQixxA3K91WBRo5Rbxi7GI9Zoc_ok'
    got       = OAK.encode(
      plain,
      key_chain:   key_chain,
      key:         'a',
      redundancy:  :none,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
    expect    = 'oak_4a_B82_MTIzNDU2Nzg5MGFi0VS5btTmPDz1lpycH94l1B0jKbQkBHtfS9ccvVEpldWjCQRALf3hUXXTBn8h-8J2uQ_ok'
    got       = OAK.encode(
      plain,
      key_chain:   key_chain,
      key:         'a',
      compression: :zlib,
      force:       true,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
  end

  def test_key_not_found_during_encryption
    assert_raises(ArgumentError) do
      OAK.encode('Woo-hoo!',key_chain: OAK::KeyChain.new({}), key: 'bogus')
    end
  end

  def test_key_not_found_during_decryption
    key_chain = OAK::KeyChain.new(
      {
        'a' => OAK::Key.new('12345678901234567890123456789012'),
      }
    )
    oak = OAK.encode('Eek!',key_chain: key_chain, key: 'a')
    assert_raises(OAK::CantTouchThisStringError) do
      OAK.decode(oak)                                  # no key_chain
    end
    assert_raises(OAK::CantTouchThisStringError) do
      OAK.decode(oak,key_chain: OAK::KeyChain.new({})) # empty
    end
  end

  def test_force_oak_4
    plain     = 'Hello!'
    key_chain = OAK::KeyChain.new(
      {
        'a' => OAK::Key.new('12345678901234567890123456789012'),
      }
    )
    #
    # Unless forced, in the absence of encryption emit oak_3.
    #
    expect    = 'oak_3CNB_2640238464_16_RjFTVTZfSGVsbG8h_ok'
    got       = OAK.encode(plain,key_chain: key_chain)
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
    #
    # Even without encryption, emit oak_4 if forced.
    #
    # Relative to the OAK_3 string above, notice how the checksum and
    # compression headers are hidden in the base64 chunk.
    #
    # Relative to other OAK_4 strings, notice the absence of an
    # encryption key name after the prefix 'oak_4'.
    #
    expect    = 'oak_4_B34_Q04yNjQwMjM4NDY0X0YxU1U2X0hlbGxvIQ_ok'
    got       = OAK.encode(plain,force_oak_4: true)
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got)
    #
    # Looking below the base64 formatting, notice the token
    # 'CN2640238464'.  The crc32 checksum, 2640238464, is unchanged from the
    # OAK_3 version above.  The 'N' indicates no compression was used.
    #
    expect    = 'oak_4_N25_CN2640238464_F1SU6_Hello!_ok'
    got       = OAK.encode(plain,force_oak_4: true,format: :none)
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got)
    #
    # To be pedantic, check that force_oak_4 is ignored when an
    # encryption key is present.
    #
    expect    = 'oak_4a_B71_MTIzNDU2Nzg5MGFikCNVKE_dzZGqOFk7akDB8R03KbQkBHtfS9ccvVEXOPXFM1U9w2bF850_ok'
    got       = OAK.encode(
      plain,
      key_chain:   key_chain,
      key:         'a',
      force_oak_4: true,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
    got       = OAK.encode(
      plain,
      key_chain:   key_chain,
      key:         'a',
      force_oak_4: false,
      debug_iv:    '1234567890ab',
    )
    assert_equal expect, got
    assert_equal plain,  OAK.decode(got,key_chain: key_chain)
  end

  # Some systematic checks that a decoding a corrupt OAK string
  # produces a hard error instead of silently returning bogus results.
  #
  # DEFENSIVE_OAK_STRINGS all use strong redundancy checks.  They all
  # use redundancy: :sha1 or are encrypted (hence enjoy GCM
  # authentication).
  #
  # For each, we test that a variety of edits produce hard errors.
  #
  DEFENSIVE_OAK_STRINGS = [
    #
    # OAK_3 with redundancy: sha1:
    #
    #   obj = [1, 2, 3]
    #   OAK.encode(obj,redundancy: :sha1)
    #   OAK.encode(obj,redundancy: :crc32)
    #   obj = {:foo=>'foo','foo'=>['x']*10}
    #   OAK.encode(obj,redundancy: :sha1)
    #   OAK.encode(obj,redundancy: :crc32)
    #
    # I've included checks at redundancy: :crc32.  Even though crc32
    # is not cryptographically strong, it is strong enough to catch
    # the limited corruptions tested here.  These corruptions are more
    # like noise or bad copy-pasta than like a message-forging attempt
    # from a well-funded enemy.
    #
    'oak_3SNB_93d431eee5bda8c932415ff77c6dbeff5bf09327_22_RjRBM18xXzJfM0kxSTJJMw_ok',
    'oak_3CNB_2690303115_22_RjRBM18xXzJfM0kxSTJJMw_ok',
    'oak_3SNB_e051b00771486ba00daf2965684cc433e3130f54_71_RjZIMl8xXzJfM180WUEzX2Zvb3NVMHNVMEExMF81XzVfNV81XzVfNV81XzVfNV81U1UxX3g_ok',
    'oak_3CNB_3325243002_71_RjZIMl8xXzJfM180WUEzX2Zvb3NVMHNVMEExMF81XzVfNV81XzVfNV81XzVfNV81U1UxX3g_ok',
    #
    # Unencrypted OAK_4 with redundancy: sha1:
    #
    #   obj = [1, 2, 3]
    #   OAK.encode(obj,redundancy: :sha1,force_oak_4: true)
    #   obj = {:foo=>'foo','foo'=>['x']*10}
    #   OAK.encode(obj,redundancy: :sha1,force_oak_4: true)
    #
    'oak_4_B79_U045M2Q0MzFlZWU1YmRhOGM5MzI0MTVmZjc3YzZkYmVmZjViZjA5MzI3X0Y0QTNfMV8yXzNJMUkySTM_ok',
    'oak_4_B128_U05lMDUxYjAwNzcxNDg2YmEwMGRhZjI5NjU2ODRjYzQzM2UzMTMwZjU0X0Y2SDJfMV8yXzNfNFlBM19mb29zVTBzVTBBMTBfNV81XzVfNV81XzVfNV81XzVfNVNVMV94_ok',
    #
    # Unencrypted OAK_4 with redundancy: sha1, exposed by format: :none:
    #
    #   obj = [1, 2, 3]
    #   OAK.encode(obj,redundancy: :sha1,force_oak_4: true,format: :none)
    #   obj = {:foo=>'foo','foo'=>['x']*10}
    #   OAK.encode(obj,redundancy: :sha1,force_oak_4: true,format: :none)
    #
    'oak_4_N59_SN93d431eee5bda8c932415ff77c6dbeff5bf09327_F4A3_1_2_3I1I2I3_ok',
    'oak_4_N96_SNe051b00771486ba00daf2965684cc433e3130f54_F6H2_1_2_3_4YA3_foosU0sU0A10_5_5_5_5_5_5_5_5_5_5SU1_x_ok',
    #
    # Encrypted OAK_4 with redundancy: :none.
    #
    #   obj = [1, 2, 3]
    #   OAK.encode(obj,redundancy: :none,key_chain: KEY_CHAIN_A,key: 'a')
    #   obj = {:foo=>'foo','foo'=>['x']*10}
    #   OAK.encode(obj,redundancy: :none,key_chain: KEY_CHAIN_A,key: 'a')
    #
    'oak_4a_B64_QadXeXzEy6JUFHQfqsvwLsSRroQ8xWQVx9TeKveglRcxUNh8m5II6rhLXt8r9ylf_ok',
    'oak_4a_B114_ZyNxEL2zMb7YgQSvp4uO5BTCQ1NIR9S3vykqFsiqzoyVB-2GG_zfazOev0fwe0wJiLi5J8dzPVNqCrvsTeIfIq0rqzGSoNLPt4OXVv7St1C4O_BvgQ_ok',
    #
    # Encrypted OAK_4 with redundancy: :sha1 (producing 2 forms of validation!)
    #
    #   obj = [1, 2, 3]
    #   OAK.encode(obj,redundancy: :sha1,key_chain: KEY_CHAIN_A,key: 'a')
    #   obj = {:foo=>'foo','foo'=>['x']*10}
    #   OAK.encode(obj,redundancy: :sha1,key_chain: KEY_CHAIN_A,key: 'a')
    #
    'oak_4a_B116_VgeSd6s34ACqOwsL_3nXDwgzXk83vV_evnNly3pvk8F95GQU6dR2R-EtJZ9ProrNFpUM7LJFeNfXqqT_bgLNF3a-09g0c-b0gRsTV9cuqt6HsgQG3A96_ok',
    'oak_4a_B166_1gQ7f-h5FrDTVSwAVQ2FLaz4obu6FZO2C3YSAbaNroucz0DZfU7c59cVugFGQnR4Q9cXWNEr8FMaYUByvRJODF2glSy3Xcoo_eXkHGw6MhRrwuEVmxa7_d7LT_ijzOU1EFcMbvGy0LAlfcqR37hupVuE2tyygq7BISPx8g_ok',
  ].freeze
  DEFENSIVE_OAK_STRINGS.each do |defensive|

    define_method "test_DEFENSIVE_decode_happily_#{defensive}" do
      obj_a = [1, 2, 3]
      obj_b = {:foo=>'foo','foo'=>['x']*10}
      got   = OAK.decode(defensive,key_chain: KEY_CHAIN_A)
      assert_includes [obj_a,obj_b], got
    end

    define_method "test_DEFENSIVE_1_byte_dels_are_hard_errors_#{defensive}" do
      defensive.size.times.each do |i|
        a         = defensive[0,i]                         # chars before pos i
        b         = defensive[i,1]                         # the 1 char at pos i
        c         = defensive[i+1,defensive.size]          # chars after pos i
        msg       = "i=#{i} a=#{a.size} b=#{b.size} c=#{c.size}"
        assert_equal   defensive,        a + b + c,    msg # confirm partition
        assert_equal   1,                b.size,       msg # confirm partition
        corrupt   = a + c                                  # b is left out!
        assert_equal   defensive.size-1, corrupt.size, msg
        assert_raises(OAK::CantTouchThisStringError,msg) do
          OAK.decode(corrupt,key_chain: KEY_CHAIN_A)
        end
      end
    end

    define_method "test_DEFENSIVE_1_byte_dupes_are_hard_errors_#{defensive}" do
      defensive.size.times.each do |i|
        a         = defensive[0,i]                         # chars before pos i
        b         = defensive[i,1]                         # the 1 char at pos i
        c         = defensive[i+1,defensive.size]          # chars after pos i
        msg       = "i=#{i} a=#{a.size} b=#{b.size} c=#{c.size}"
        assert_equal   defensive,        a + b + c,    msg # confirm partition
        assert_equal   1,                b.size,       msg # confirm partition
        corrupt = a + b + b + c                            # b is duplicated!
        assert_equal   defensive.size+1, corrupt.size, msg
        assert_raises(OAK::CantTouchThisStringError,msg) do
          OAK.decode(corrupt,key_chain: KEY_CHAIN_A)
        end
      end
    end

    define_method "test_DEFENSIVE_1_bit_toggles_are_hard_errors_#{defensive}" do
      #
      # All of our DEFENSIVE_OAK_STRINGS have format: :base64.
      #
      # As such, there can be bits in the last byte of content which
      # are irrelevant.
      #
      usually_bits = [ 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40       ]
      always_bits  = [                                           0x80 ]
      defensive.size.times.each do |i|
        a         = defensive[0,i]                         # chars before pos i
        b         = defensive[i,1]                         # the 1 char at pos i
        c         = defensive[i+1,defensive.size]          # chars after pos i
        msg       = "i=#{i} a=#{a.size} b=#{b.size} c=#{c.size}"
        assert_equal   defensive,        a + b + c,    msg # confirm partition
        assert_equal   1,                b.size,       msg # confirm partition
        test_bits = ('_ok' == c) ? always_bits : (usually_bits + always_bits)
        test_bits.each do |bit|
          corrupt = a + (b.ord ^ bit).chr + c              # b has bit toggled!
          assert_equal defensive.size,   corrupt.size, msg + " bit=#{bit}"
          assert_raises(OAK::CantTouchThisStringError,msg + " bit=#{bit}") do
            OAK.decode(corrupt,key_chain: KEY_CHAIN_A)
          end
        end
      end
    end

    define_method "test_DEFENSIVE_2_byte_swaps_are_hard_errors_#{defensive}" do
      defensive.size.times.each do |i|
        a         = defensive[0,i]                         # chars before pos i
        b         = defensive[i,1]                         # the 1 char at pos i
        c         = defensive[i+1,defensive.size]          # chars after pos i
        msg       = "i=#{i} a=#{a.size} b=#{b.size} c=#{c.size}"
        assert_equal   defensive,        a + b + c,    msg # confirm partition
        assert_equal   1,                b.size,       msg # confirm partition
        next if 0 == c.size                                # avoid degeneration
        c.size.times.each do |j|
          ca     = c[0,j]                                  # chars before pos j
          cb     = c[j,1]                                  # the 1 char at pos j
          cc     = c[j+1,c.size]                           # chars after pos j
          m      = "#{msg} ca=#{ca.size} cb=#{cb.size} cc=#{cc.size}"
          assert_equal c,                ca + cb + cc, m   # confirm partition
          assert_equal 1,                cb.size,      m   # confirm partition
          assert_equal defensive,        a+b+ca+cb+cc, m   # confirm partition
          next if b == cb                                  # avoid mirrors
          corrupt = a + cb + ca + b + cc                   # b and cb swapped!
          assert_equal defensive.size,   corrupt.size, m
          assert_raises(OAK::CantTouchThisStringError,m) do
            OAK.decode(corrupt,key_chain: KEY_CHAIN_A)
          end
        end
      end
    end

  end

  # When doing the DEFENSIVE_OAK_STRINGS work above, two specific
  # bit-twiddled strings were revealed as unusual.
  #
  # When they pass OAK.decode(corrupt,key_chain: KEY_CHAIN_A), a debug
  # warning is emitted to STDOUT from malloc()!
  #
  # I have captured those here for reference.
  #
  # In both cases it seems that in the very special case of
  # bit-twiddling of a base64 stream in an unencrypted OAK_4 stream we
  # can convert the compression flag from N (none) to M (lzma), and
  # then we incorrectly pass un-compressed FRIZZY data to LZMA.decode.
  # The LZMA code then engenders the malloc() on STDOUT warning like:
  #
  #   ruby(81351,0x7fffa6a80380) malloc: *** mach_vm_map(size=5274077123616858112) failed (error code=3)
  #   *** error: can't allocate region
  #   *** set a breakpoint in malloc_error_break to debug
  #
  SPECIFIC_MAGIC_OAK_CORRUPTION = [
    'oak_4_B128_U01lMDUxYjAwNzcxNDg2YmEwMGRhZjI5NjU2ODRjYzQzM2UzMTMwZjU0X0Y2SDJfMV8yXzNfNFlBM19mb29zVTBzVTBBMTBfNV81XzVfNV81XzVfNV81XzVfNVNVMV94_ok',
    'oak_4_B79_U005M2Q0MzFlZWU1YmRhOGM5MzI0MTVmZjc3YzZkYmVmZjViZjA5MzI3X0Y0QTNfMV8yXzNJMUkySTM_ok',
    #
    # OAK_3 are not different than unencrypted OAK_4 in this regard.
    # After hunting for deeper understanding of what is going on, I was
    # able to synthesize a similarly-corrupt OAK string like so:
    #
    #   2.1.6 :006 > str = OAK.encode(obj,redundancy: :none,format: :none)
    #   => "oak_3NNN_0_16_F4A3_1_2_3I1I2I3_ok"
    #   2.1.6 :010 > str[6] = 'M' # convert compression byte to LZMA code
    #   => "M"
    #   2.1.6 :011 > str
    #   => "oak_3NMN_0_16_F4A3_1_2_3I1I2I3_ok"
    #
    # This also produces the mysterious low-level warning when decoded:
    #
    #   2.1.6 :008 > OAK.decode('oak_3NMN_0_16_F4A3_1_2_3I1I2I3_ok')
    #   irb(2617,0x7fffa6a80380) malloc: *** mach_vm_map(size=5274077123616858112) failed (error code=3)
    #   *** error: can't allocate region
    #   *** set a breakpoint in malloc_error_break to debug
    #
    # I have decided *not* to alter OAK_4 so that the compression flag
    # (and possibly other headers) are defended by the redundancy
    # field.  Users who want that level of authentication should use
    # the encryption feature.
    #
    'oak_3NMN_0_16_F4A3_1_2_3I1I2I3_ok',
  ].freeze
  SPECIFIC_MAGIC_OAK_CORRUPTION.each do |corrupt|
    define_method "test_SPECIFIC_MAGIC_OAK_CORRUPTION_#{corrupt}" do
      assert_raises(OAK::CantTouchThisStringError) do
        OAK.decode(corrupt,key_chain: KEY_CHAIN_A)
      end
    end
  end

  # When doing the DEFENSIVE_OAK_STRINGS work above, and digging
  # deeper into the SPECIFIC_MAGIC_OAK_CORRUPTION above, I traced down
  # to find which specific values make LZMA.decode unhappy.
  #
  # I have captured those here for reference.
  #
  # When run, these produce warnings like:
  #
  #   ruby(82213,0x7fffa6a80380) malloc: *** mach_vm_map(size=6427867242409648128) failed (error code=3)
  #   *** error: can't allocate region
  #   *** set a breakpoint in malloc_error_break to debug
  #
  SPECIFIC_MAGIC_LZMA_CORRUPTION = [
    'F4A3_1_2_3I1I2I3',                                      # bad LZMA sequence
    'F6H2_1_2_3_4YA3_foosU0sU0A10_5_5_5_5_5_5_5_5_5_5SU1_x', # bad LZMA sequence
  ].freeze
  SPECIFIC_MAGIC_LZMA_CORRUPTION.each do |corrupt|
    define_method "test_SPECIFIC_MAGIC_OAK_CORRUPTION_#{corrupt}" do
      assert_raises(RuntimeError) do
        LZMA.decompress(corrupt)
      end
    end
  end

end
