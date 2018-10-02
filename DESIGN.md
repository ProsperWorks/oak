# OAK: The Object ArKive

## All that to avoid JSON?

OAK is a serialization and envelope format which encodes simple Ruby
objects as strings.  It bundles together a variety of well-understood
encoding libraries into a succinct self-describing package.

This document covers the existing OAK format, and proposed encryption
extension.

OAK compares to JSON, YAML, and Marshal.  OAK is more precise than
JSON or YAML, but slightly more Ruby-esque, and supports fewer types
than Marshal.  OAK also has features similar to OpenPGP
([https://tools.ietf.org/html/rfc4880](https://tools.ietf.org/html/rfc4880))
(though not, so far, encryption).

The main value proposition for OAK is operational flexibility.  OAK
leds you defer choices between compression, checksumming, and 7-bit
cleanliness algorithms until after a system is live and under load.

As of 2017-09-13, OAK is used by `ALI` (copper.com's primary web
service) for volatile caches in Redis, durable archives in S3, and for
7-bit clean encoding of complex configuration data.

Author: [JHW](https://github.com/jhwillett)
Advisors: Marshall, Gerald, Kelly, Neil

Here is a sneak preview of some OAK strings:
```
$ echo 'HelloWorld!' | bin/oak.rb --format none
oak_3CNN_1336599037_18_F1SU11_HelloWorld!_ok

$ echo 'HelloWorld!' | bin/oak.rb
oak_3CNB_1336599037_24_RjFTVTExX0hlbGxvV29ybGQh_ok

$ echo 'HelloWorld!' | bin/oak.rb --compression lz4 --force
oak_3C4B_1336599037_28_EvADRjFTVTExX0hlbGxvV29ybGQh_ok

$ echo 'HelloWorld!' | bin/oak.rb | bin/oak.rb --mode decode-lines
HelloWorld!
```

## OAK Version History

OAK has been live for 16 months by the time this arch document was
prepared retroactively.

* [https://github.com/ProsperWorks/ALI/pull/1245](https://github.com/ProsperWorks/ALI/pull/1245) **oak**
    * Merged to major_2016_04_dragonfruit.
    * Initial implementation. Not integrated or active.
    * Version oak_1
* [https://github.com/ProsperWorks/ALI/pull/1350](https://github.com/ProsperWorks/ALI/pull/1350) **oak-in-summary_accessor**
    * Merged to major_2016_04_dragonfruit.
    * Reworked SummaryAccessor with ENV flag to switch to OAK serialization.
    * Exposure to live data revealed some issues missed in the lab.
* [https://github.com/ProsperWorks/ALI/pull/1631](https://github.com/ProsperWorks/ALI/pull/1631) **oak-remove-json-and-yaml**
    * Merged to major_2016_06_goat.
    * Simplified down to only the one serialization algorithm, "FRIZZY".
    * Version oak_2
* [https://github.com/ProsperWorks/ALI/pull/1618](https://github.com/ProsperWorks/ALI/pull/1618) **fix-oak-utf8**
    * Merged in major_2016_06_goat.
    * Fixed issues uncovered in SummaryAccessor ramp.
    * Version oak_3
* [https://github.com/ProsperWorks/ALI/pull/1655](https://github.com/ProsperWorks/ALI/pull/1655) **volatile_cache_accessor**
    * Merged in major_2016_06_goat.
    * Introduced RedisCache.  Later PRs use RedisCache for
        * SummaryAccessor (OAK)
        * RussianDoll caches (Marshal+OAK)
        * S3 cache (OAK)
        * COMPANY_ID_CACHE (JSON)
    * Commits to OAK for volatile use cases.
* [https://github.com/ProsperWorks/ALI/pull/1757](https://github.com/ProsperWorks/ALI/pull/1757) **oak-woe-2016-06-30**
    * Merged in major_2016_07_hotpocket.
    * Fixed a regexp which had broken some Float parsing.
* [https://github.com/ProsperWorks/ALI/pull/1724](https://github.com/ProsperWorks/ALI/pull/1724) **correspondences-in-s3-fixes**
    * Merged in major_2016_07_hotpocket.
    * Stores Correspondence bodies in S3 as OAK strings.
    * Commits to OAK for durable use cases at oak_3.

See also [OAK: Encryption-in-OAK](ENCRYPTION.md) for later
developments and the introduction of OAK_4.

## Overview of OAK strings.

`OAK.encode` includes a manifest of its options explicitly in the
OAK string output.  There is no need for an options back channel to
`OAK.decode`.

We could encode every OAK string with different options, and
`OAK.decode` can reverse all of them with no extra info.
```
>> OAK.encode('HelloWorld',redundancy: :none)
=> "oak_3NNB_0_23_RjFTVTEwX0hlbGxvV29ybGQ_ok"

>> OAK.encode('HelloWorld',format: :none,redundancy: :none)
=> "oak_3NNN_0_17_F1SU10_HelloWorld_ok"

>> OAK.encode('HelloWorld',compression: :zlib,force: true)
=> "oak_3CZB_3789329355_34_eJxzMwwONTSI90jNyckPzy_KSQEAL2gF3A_ok"

>> OAK.decode(OAK.encode('HelloWorld',redundancy: :none))
=> "HelloWorld"

>> OAK.decode(OAK.encode('HelloWorld',format: :none,redundancy: :none))
=> "HelloWorld"

>> OAK.decode(OAK.encode('HelloWorld',compression: :zlib,force: true))
=> "HelloWorld"
```

We use this to defer our choice of time-space tradeoffs until runtime.
`ALI`'s `Caches::RedisCache` mechanism enshrines this pattern by parsing
OAK options from the ENV:
```
# in Caches::RedisCache#_serialize
OAK.encode(
 pre_obj,
 redundancy:  (ENV["CACHE_OAK_REDUNDANCY_#{name}"] || 'sha1').intern,
 compression: (ENV["CACHE_OAK_COMPRESSION_#{name}"]|| 'bzip2').intern,
 force:       (ENV["CACHE_OAK_FORCE_#{name}"]      == 'true'),
 format:      (ENV["CACHE_OAK_FORMAT_#{name}"]     || 'base64').intern,
)
```
These defaults differ from those in `OAK.encode`.

Here is a quick parse of some OAK strings.
```
>> OAK.encode('Hi',format: :none)

=> "oak_3CNN_3475096913_8_F1SU2_Hi_ok"
    oak_3                                         # OAK ver 3
         C                                        # checksum Crc32
          N                                       # compression None
           N                                      # format None
             3475096913                           # checksum value
                        8                         # 8 data bytes
                          F1SU2_Hi                # data
                                   ok             # end of sequence

>> OAK.encode([1,'2'],redundancy: :none,format: :none)

=> "oak_3NNN_0_15_F3A2_1_2I1SU1_2_ok"
    oak_3                                         # OAK ver 3
         N                                        # checksum None
          N                                       # compression None
           N                                      # format None
             0                                    # checksum value
               15                                 # 15 data bytes
                  F3A2_1_2I1SU1_2                 # data
                                  ok              # end of sequence
```
The FRIZZY format encodes all the objects in the graph as a vector,
with the element 0 implicitly the top-level object and compound
objects encoded with indices into the main object vector.
```
                  F                               # FRIZZY serializer
                   3                              # 3 objects
                    A2_1_2                        # obj 0 an Array
                                                  #    w/ 2 slots:
                                                  #      obj 1 and
                                                  #      obj 2 
                          I1                      # obj 1 Int 1
                            SU1_2                 # obj 2 Str
                                                  #   UTF-8
                                                  #   1 string bytes
                                                  #   bytes '2'
```

## option :redundancy => :crc32, :none, or :sha1

The `:redundancy` option selects which algorithm is used to compute
the checksum included by OAK.encode.  This checksum lets OAK.decode
detect stream errors.The choice of `:redundancy` at encode time is
recorded in the 6th character of the OAK string.

`:redundancy => :crc32`, the default, is flagged as a `C` and is
`'%d' % Zlib.crc32(str)`.

Advantages:

* Encodes in only 12 bytes.
* Plenty good enough for all natural stream errors.

Disadvantages:

* Encodes in 12 whole bytes!
* Easily spoofed: not cryptographically secure. 

`:redundancy => :none`, is flagged as a `N` and is simply `_0`.

I chose to leave an explicit place-holder field even at the cost of 2
useless bytes to keep the number of meta-data field constant.

Advantages:

* Encodes in only 2 bytes.
* OAK will still catch truncation errors.

Disadvantages:

* Encodes in 2 whole bytes!
* OAK will not catch twiddled bits.
  * All compression algorithms do their own checksumming.
  * So this is only a disadvantage with `:compression => :none`.
    * Caution: `:force => false` is default.
    * So fallback to `:compression => :none` is likely.
    * So `:compression` is not a substitute for `:redundancy`.

`:redundancy => :sha1`, is flagged as a `S`.  It is very large and is
not recommended for most use cases.

Advantages:

* Harder for a malicious hacker to fool.

Disadvantages:

* Encodes in 41 bytes!

## option :compression => :none, :lz4, :zlib, :bzip2, or :lzma

`:compression` is recorded in the 7th char and selects which
algorithm compresses the payload.

`:compression => :none`, the default, is flagged as a `N`.  No compression.

* No compression or decompression costs.
* Human-readable if the source content is human readable and format is none.

`:compression => :lz4` is flagged as a `4`.  [LZ4](https://github.com/lz4/lz4) is in the [Lempel-Ziv](https://en.wikipedia.org/wiki/LZ77_and_LZ78) family of dictionary-based redundancy eaters which are popular for low-latency online systems

* Low compression costs, low decompression costs.
* Compression ratios in 1.8-2.1 for English.

`:compression => :zlib` is flagged as a `Z`.  [RFC 1951 Zlib ](https://en.wikipedia.org/wiki/DEFLATE)is the widely-used compression used in pkzip, zip, and gzip.  It crunches LZ77 with a follow-on Huffman step.

* Medium compression costs, medium decompression costs.
* Compression ratios around 4.0 for English.

`:compression => :bzip2` is flagged as a `B`.  [Burroughs-Wheeler transform](https://en.wikipedia.org/wiki/Bzip2) with some Huffman, delta, and sparse array encoding thrown in for good measure.

* Higher compression and decompression costs.
* Compression ratios around 5.0 for English.

`:compression => :lzma` is flagged as a `M` uses the [Lempel-Zib_Markov chain algorithm](https://en.wikipedia.org/wiki/Lempel%E2%80%93Ziv%E2%80%93Markov_chain_algorithm).  It is an unusual choice for an online system.

Advantages:

* Very high compression costs, medium-low decompression costs.
* Compression ratios around 5.2 for English.

`option :force => false, true`

By default, `OAK.encode` will fall back to `:compression => :none` if
the compressed string is larger than the source string.

`:force => true` overrides this fail safe.

## option :format => :base64 or :none

The `:format` option selects the character set used in the main body
of the OAK string - the payload part which follows the flags and
checksum and before the `_ok` terminator.  The choice of `:redundancy`
at encode time is recorded in the 8th character of the OAK string.

`:format => :base64`, the default, is flagged as a `B` and is
`Base64.urlsafe_encode64(str)` with the final `===` padding stripped.

Advantages:

* 7-bit clean (not that it matters in the TCP age)
* Prints prettily in ASCII terminals and editors.
* Easy to eyeball: no spaces, commas, slashes, colons, etc.
* In most text GUIs, the auto-highlighting feature when you
  double-click an OAK string will exactly select it.
    * Personally, this is my favorite feature of OAK.

Disadvantages:

* Not human readable.
    * Only matters when compression is off.
* Size bloat in the ratio of 6 bits to 8 bits i.e. by a factor of 133%.
    * Reverses some compression gains.

`:format => :none` is flagged as a `N` and does nothing.  The source
string, including zeros, bells, form feeds, and umlauts are all are
catenated nakedly into the OAK string.

Advantages:

* Human-readable if the source content is human readable.
* No size bloat.

Disadvantages:

* Hard to parse visually in most cases.
* Nasty in logs when data is binary or compressed.

## Why FRIZZY?  Why not JSON, YAML, XML, or Marshal?

JSON treats everything as a value type - it knows nothing about object
identity.

In Ruby, each distinct string literal is a distinct String
object. There is a subtle difference between a pair of equivalent
Strings and a pair of identical strings:
```
>>            arr = ['x','x'] ; arr[0].object_id == arr[1].object_id
=> false

>> str = 'x'; arr = [str,str] ; arr[0].object_id == arr[1].object_id
=> true
```
JSON is the same for `['x','x']` and `[str,str]`.  The difference
is lost in translation.
```
>> str = 'x' ; JSON.dump([str,str]) == JSON.dump(['x','x'])
=> true

>> JSON.dump(['x','x'])
=> "[\"x\",\"x\"]"

>> str = 'x' ; JSON.dump([str,str])
=> "[\"x\",\"x\"]"

>> arr = JSON.load(JSON.dump([str,str]))
=> ["x", "x"]

>> arr[0].object_id == arr[1].object_id
=> false
```
With OAK, vive la différence:
```
>> str = 'x' ; OAK.encode([str,str]) == OAK.encode(['x','x'])
=> false

>> OAK.encode(['x','x'],format: :none)
=> "oak_3CNN_3737537744_16_F3A2_1_2SU1_xsU0_ok"

>> str = 'x' ; OAK.encode([str,str],format: :none)
=> "oak_3CNN_2865617390_13_F2A2_1_1SU1_x_ok"
```

The JSON format does not support `Infinity`, `-Infinity`, or `NaN` -
though Ruby's JSON encoder transcodes thes via a nonstandard
extension.

YAML handles `Infinity`, `-Infinity`, and `NaN`.  YAML also handles
DAGs - but not cycles.

XML is ... XML.  And huge.  And Nokogiri is weird.

Who cares?  These are just strings.  It's better to treat them as
immutable anyhow, right? What about compound objects like lists or
hashes?

It turns out that capturing identity is the key to serializing any
non-tree objects.
```
>> a = ['a','TBD']
=> ["a", "TBD"]

>> b = ['b',a]
=> ["b", ["a", "TBD"]]

>> a[1] = b                                  # a cycle!
=> ["b", ["a", [...]]]                   

>> JSON.dump(a)
SystemStackError: stack level too deep

>> OAK.encode(a,format: :none)
=> "oak_3CNN_3573295141_24_F4A2_1_2SU1_aA2_3_0SU1_b_ok"
```
The essence of serializing non-tree objects is capturing identity.

Does this matter in `ALI`?  Honestly, I don't know.  Cycles and DAGs are
irrelevant for Correspondence bodies.  We do have Summaries which are
DAGgy on Strings but that is probably irrelevant in all logic.

But "Do we need it?" is the wrong question.  Data in the wild is
diverse and surprising.  The right question is, "Can we *prove* that
we do not need it now or tomorrow?"  With a cycle-aware serializer, I
don't *need* to prove nonexistence or constrain the future.

What about
[Marshal](http://jakegoulding.com/blog/2013/01/15/a-little-dip-into-rubys-marshal-format/)?
It handles (almost) all Ruby types including user-defined classes, has
no problems with cycles, and is widely available and accepted.

My reasons for not using Marshal are:

* Security
    * [https://ruby-doc.org/core-2.2.2/Marshal.html](https://ruby-doc.org/core-2.2.2/Marshal.html)
    * "By design, `load` can deserialize almost any class loaded into
      the Ruby process. In many cases this can lead to remote code
      execution if the Marshal data is loaded from an untrusted
      source."
    * Marshal can have problems if a user-defined class changes between
      encoding time and decoding time.
    * I wanted OAK to refuse to encode objects whose structure it
      could not guarantee to recover with perfect fidelity.
* I have ambitions for language portability with in OAK.
    * Specious: porting a subset of Marshal would be no harder than
      porting OAK.

To be fair, we use Marshal anyhow, wrapped in OAK, in our cache layers
which store full ActiveRecord model objects.  So any arguments about
architectural purity vis-a-vis OAK are part hype.
