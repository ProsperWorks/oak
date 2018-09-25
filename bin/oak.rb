#!/usr/bin/env ruby
#
# oak.rb: cli driver for encoding strings in the OAK format.
#
# author: jhw@prosperworks.com
# incept: 2016-03-05
#

# This is *not* a Rails program, though it does require some code from
# ALI.
#
require_relative '../lib/util/oak.rb'
require          'optimist'

OLD_ARGV = ARGV.dup            # ARGV is consumed by Optimist but we use later.
OPTS     = Optimist.options do
  banner "#{$0} cli driver for OAK"
  banner <<-EOS
Examples:
  $ echo hello | bin/oak.rb
  oak_3CNB_1944283675_15_RjFTVTVfaGVsbG8_ok
  $ (echo hello ; echo world) | bin/oak.rb
  oak_3CNB_1944283675_15_RjFTVTVfaGVsbG8_ok
  oak_3CNB_2139413982_15_RjFTVTVfd29ybGQ_ok
  $ (echo hello ; echo world) | bin/oak.rb --compression zlib --force
  oak_3CZB_1944283675_26_eJxzMwwONY3PSM3JyQcAFF4DyA_ok
  oak_3CZB_2139413982_26_eJxzMwwONY0vzy_KSQEAFNgD3A_ok
  $ (echo hello ; echo world) | bin/oak.rb --format none
  oak_3CNN_1944283675_11_F1SU5_hello_ok
  oak_3CNN_2139413982_11_F1SU5_world_ok
  $ (echo hello ; echo world) | bin/oak.rb | bin/oak.rb --mode decode-lines
  hello
  world
EOS
  banner "Options:"
  opt :redundancy,   'redundancy',                   :default => 'crc32'
  opt :format,       'format',                       :default => 'base64'
  opt :compression,  'compression',                  :default => 'none'
  opt :force,        'compress even if bigger',      :default => false
  opt :mode,         'mode',                         :default => 'encode-lines'
  opt :key_chain,    'key chain env name',           :type    => :string
  opt :key,          'encrypt key name',             :type    => :string
  opt :key_check,    'check available keys',         :default => false
  opt :key_generate, 'generate new key',             :default => false
  opt :force_oak_4,  'force OAK_4 even unencrypted', :default => false
  opt :eigen,        'calc eigenratio',              :type    => :int
  opt :self_test,    'self-test only',               :default => false
  opt :help,         'show this help'
end
Optimist::die :eigen, "must be non-negative" if OPTS[:eigen] && OPTS[:eigen] < 0

oak_opts               = {}
oak_opts[:redundancy]  = OPTS[:redundancy]
oak_opts[:compression] = OPTS[:compression]
oak_opts[:force]       = OPTS[:force]
oak_opts[:format]      = OPTS[:format]
oak_opts[:key_chain]   = OAK.parse_env_chain(ENV,OPTS[:key_chain])
oak_opts[:key]         = OPTS[:key]
oak_opts[:force_oak_4] = OPTS[:force_oak_4]

if !OAK::REDUNDANCY_2_CODE.keys.include?(oak_opts[:redundancy])
  Optimist::die :redundancy, "bogus #{OPTS[:redundancy]}"
end
if !OAK::COMPRESSION_2_CODE.keys.include?(oak_opts[:compression])
  Optimist::die :compression, "bogus #{OPTS[:compression]}"
end
cool_formats = OAK::FORMAT_2_CODE.keys
if !cool_formats.include?(oak_opts[:format])
  Optimist::die :format, "bogus #{OPTS[:format]} not in #{cool_formats}"
end

=begin

doctest: simple transcoding
>> OAK::decode(OAK::encode([1,"2",3.000001]))
=> [1,"2",3.000001]
>> OAK::decode(OAK::encode({foo: "bar"}))
=> {foo: "bar"}
>> OAK::decode(OAK::encode({foo: :bar}))
=> {foo: :bar}
>> OAK::decode(OAK::encode("Hello, World!"))
=> "Hello, World!"
>> OAK::decode(OAK::encode("Hello, World!", format: :none, redundancy: :none))
=> "Hello, World!"

doctest: stability of encoding
>> OAK::decode("oak_3NNB_0_30_RjNIMV8xXzJZQTNfZm9vU1UzX2Jhcg_ok")
=> {:foo=>"bar"}
>> OAK::encode(1, format: :base64, redundancy: :none)
=> "oak_3NNB_0_6_RjFJMQ_ok"
>> OAK::encode(1, format: :base64, redundancy: :crc32)
=> "oak_3CNB_3405226796_6_RjFJMQ_ok"
>> OAK::encode(1, format: :none, redundancy: :crc32)
=> "oak_3CNN_3405226796_4_F1I1_ok"
>> hello_utf8 = "Hello, World!".force_encoding('UTF-8')
=> "Hello, World!"
>> OAK::encode(hello_utf8, format: :base64, redundancy: :none)
=> "oak_3NNB_0_27_RjFTVTEzX0hlbGxvLCBXb3JsZCE_ok"
>> OAK::encode(hello_utf8, format: :none,   redundancy: :crc32)
=> "oak_3CNN_2351984628_20_F1SU13_Hello, World!_ok"

Note above I used force_encoding('UTF-8') after discovering that with
Ruby 2.1.6 on Mac I get Encoding.default_encoding is UTF-8, but with
Ruby 2.1.6 on Linux I get Encoding.default_encoding is US-ASCII!

=end

if __FILE__ == $0
  if OPTS[:self_test]
    require 'rubydoctest'
    exit RubyDocTest::Runner.new(File.read(__FILE__), __FILE__).run ? 0 : 1
  end
  if OPTS[:key_check]
    if !OPTS[:key_chain]
      puts "no --key-chain specified"
    else
      keys = oak_opts[:key_chain].keys.keys
      if 0 == keys.size
        puts "#{OPTS[:key_chain]}: no keys found"
      else
        puts "#{OPTS[:key_chain]}: found keys: #{keys.join(' ')}"
      end
    end
  end
  if OPTS[:key_generate]
    STDOUT.puts OAK.encode(OAK.random_key)
    exit 0
  end
  if !$stdin.tty?
    if OPTS[:eigen]
      prev = STDIN.read
      puts "input: %d" % prev.size
      OPTS[:eigen].times do |i|
        oak   = OAK.encode(prev,oak_opts)
        psize = prev.size
        wsize = oak.size
        ratio = 1.0 * wsize / psize
        puts "  iter %3d: %4d => %4d ratio %.2f" % [i,psize,wsize,ratio]
        prev  = oak
      end
      exit 0
    end
    unhappiness = 0
    case OPTS[:mode]
    when 'cat'
      ARGF.each_line.map(&:strip).each do |line|
        puts line
      end
    when 'encode-lines'
      ARGF.each_line.map(&:strip).each do |line|
        puts OAK.encode(line,oak_opts)
      end
    when 'decode-lines'
      ARGF.each_line.map(&:strip).each do |line|
        puts OAK.decode(line,oak_opts)
      end
    when 'encode-file'
      puts OAK.encode(STDIN.read,oak_opts)
    when 'decode-file'
      STDOUT.write OAK.decode(STDIN.read.strip,oak_opts)
    when 'recode-file'
      puts OAK.encode(OAK.decode(STDIN.read,oak_opts),oak_opts)
    when 'crazy'
      #
      # --mode crazy prints out a sample of OAK strings for various
      # challenging cases.
      #
      cycle_a    = ['cycle_a','TBD']
      cycle_b    = ['cycle_b',cycle_a]
      cycle_a[1] = cycle_b
      dag_c      = ['dag_c']
      dag_b      = ['dag_b',dag_c]
      dag_a      = ['dag_a',dag_b,dag_c]
      [
        'hello',
        ['hello'] + ['hello',:hello] * 2,
        {1=>'a','b'=>2,[]=>3,''=>4,{}=>5,nil=>6},
        ['x','x','x','x','x','x','x','x','x','x','x','x','x'],
        ['x'] * 13,
        cycle_a,
        dag_a,
        [1,-123,0.12,-0.123,Float::NAN,-Float::INFINITY,3.14159265358979],
      ].each do |obj|
        oak = OAK.encode(obj,redundancy: :crc32, format: :none, compression: :none)
        puts ""
        puts "obj:   #{obj}"
        puts "  oak: #{oak}"
        begin
          dec = OAK.decode(oak,oak_opts)
          if dec != obj
            if !dec.is_a?(Float) && !enc.is_a?(Float) && !dec.nan? && !enc.nan?
              unhappiness += 1
              puts "  BAD: #{dec}"
            end
          end
        rescue OAK::CantTouchThisStringError => ex
          puts "  BAD: #{ex.message}: #{ex.backtrace_locations[0]}"
          unhappiness += 1
        end
      end
    when 'tests'
      [
        [1,2,3],
        {:foo=>'foo','foo'=>['x']*10},
        -1,
        Float::NAN,
        nil,
      ].each do |obj|
        puts "    #{obj} => ["
        key_chain = OAK::KeyChain.new(
          { 'l0ng3r' => OAK::Key.new('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') }
        )
        [
          {redundancy: :none,  format: :none,   compression: :none},
          {redundancy: :none,  format: :base64, compression: :lz4,   force: true},
          {redundancy: :crc32, format: :base64, compression: :zlib,  force: true},
          {redundancy: :crc32, format: :base64, compression: :bzip2, force: true},
          {redundancy: :sha1,  format: :base64, compression: :lzma,  force: true},
          {key_chain: key_chain, force_oak_4: true, format: :none,              },
          {key_chain: key_chain, force_oak_4: true,                             },
          {key_chain: key_chain, key: 'l0ng3r',                                 },
        ].each do |opts|
          oak = OAK.encode(obj,opts)
          puts "      '#{oak}',"
          dec = OAK.decode(oak,opts)
          if dec != obj
            if !dec.is_a?(Float) && !enc.is_a?(Float) && !dec.nan? && !enc.nan?
              unhappiness += 1
            end
          end
        end
        puts "    ],"
      end
    else
      Optimist::die :mode, "bogus mode #{OPTS[:mode]}"
    end
    if unhappiness > 0
      puts "unhappiness: #{unhappiness}"
    end
    exit unhappiness
  end
end
