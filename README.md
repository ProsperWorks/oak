# oak

OAK is an encoding format with enough polymorphism to support run-time
performance experimentation and some light encryption-at-rest.

OAK supports built-in switchability between common algorithms:

  - Checksumming with ZLIB crc32(), SHA1, or none.
  - Compression with LZ4, ZLIB, BZIP2k, LZMA, or none.
  - ASCII armor with base64, or none.

OAK also supports optional AES-256-GCM encryption with full 96-bit
random IVs and 16 byte auth tags.

OAK is also a compact serialization format for primitive Ruby objects
like String, Symbol, Integer, Float, Hash, and Array.  OAK
serialization supports cyclical structures and distinguishes between
String and Symbol, but does not support user-defined types.

In ProsperWorks/ALI, we use OAK at Copper, OAK has found use cases in:

  - Volatile Redis cache entries, where dynamic control of time-space
    tradeoffs shaves down hosting costs.
  - Durable cold archives of larger user data.
  - Encrypting runtime secrets.

OAK is not human-readable.  It is intended to be an interchange or
archive format, not as a human interface.

Consider OAK if you are dealing with content at scale and are not
quite happy with JSON, YAML, XML, or Ruby's Marshal format.  Disregard
OAK your needs are all met by JSON.

## Using in Ruby
```
2.1.6 :001 > require 'oak'
 => true
2.1.6 :002 > h = { 'one' => 1, 'array' => [ true, false ] }
 => {"one"=>1, "array"=>[true, false]}
2.1.6 :003 > OAK.encode(h)
 => "oak_3CNB_2774455364_51_RjdIMl8xXzJfM180U1UzX29uZUkxU1U1X2FycmF5QTJfNV82dGY_ok"
2.1.6 :004 > OAK.encode(h,format: :none)
 => "oak_3CNN_2774455364_38_F7H2_1_2_3_4SU3_oneI1SU5_arrayA2_5_6tf_ok"
2.1.6 :005 > OAK.encode(h, compression: :bzip2, force: true)
 => "oak_3CBB_2774455364_106_QlpoOTFBWSZTWag9FGUAAAaPgD-AIWAKAKMBlCAgADFGjIGjTI0Ip-lPRGynomJ-qPMBxIQDw5vmY9SVFxhFj7ZLMSPxdyRThQkKg9FGUA_ok"
2.1.6 :006 > OAK.encode(h, compression: :bzip2)
 => "oak_3CNB_2774455364_51_RjdIMl8xXzJfM180U1UzX29uZUkxU1U1X2FycmF5QTJfNV82dGY_ok"
2.1.6 :007 > OAK.decode('oak_3CNB_2774455364_51_RjdIMl8xXzJfM180U1UzX29uZUkxU1U1X2FycmF5QTJfNV82dGY_ok')
 => {"one"=>1, "array"=>[true, false]}
```

## Using in Shell
```
$ echo hello | bin/oak --mode encode-file
oak_3CNB_911092726_16_RjFTVTZfaGVsbG8K_ok
$ echo oak_3CNB_911092726_16_RjFTVTZfaGVsbG8K_ok | bin/oak --mode decode-file
hello
$ echo hello | bin/oak --mode encode-file --compression lz4 --force true
oak_3C4B_911092726_19_DMBGMVNVNl9oZWxsbwo_ok
$ echo oak_3C4B_911092726_19_DMBGMVNVNl9oZWxsbwo_ok | bin/oak --mode decode-file
hello
```

## Using in Shell for Encryption
```
$ bin/enigma.rb --keygen
oak_3CNB_2975186575_52_RjFTQTMyX00du8vD8WAikhLNgdnaOYtQV6uqyNqRz6modiEcJHOl_ok
$ bin/enigma.rb --keygen
oak_3CNB_1324948677_52_RjFTQTMyXytCueDDTpEOusKkPMANgaA9zsJuvOend5DCIJWwJdjC_ok
$ export ENIGMA_KEYS=foo,bar
$ export ENIGMA_KEY_foo=oak_3CNB_2975186575_52_RjFTQTMyX00du8vD8WAikhLNgdnaOYtQV6uqyNqRz6modiEcJHOl_ok
$ export ENIGMA_KEY_bar=oak_3CNB_1324948677_52_RjFTQTMyXytCueDDTpEOusKkPMANgaA9zsJuvOend5DCIJWwJdjC_ok
$ echo hello | bin/enigma --encrypt
oak_4foo_B59_Si1VQNhf1qZFS31cMVF1ijVcyGV4SUzgr_19QQ0FZ8MFIbIR0D8rT3Ao3W8_ok
$ echo hello | bin/enigma --encrypt
oak_4foo_B59_LLmwT44ZPWRqFsktyInJAa5L8haeVovJ_lbc05BgAfQXmMHAZdRXkx4nSj4_ok
$ echo oak_4foo_B59_Si1VQNhf1qZFS31cMVF1ijVcyGV4SUzgr_19QQ0FZ8MFIbIR0D8rT3Ao3W8_ok | bin/enigma --decrypt
hello
$ echo oak_4foo_B59_LLmwT44ZPWRqFsktyInJAa5L8haeVovJ_lbc05BgAfQXmMHAZdRXkx4nSj4_ok | bin/enigma --decrypt
hello
```

## Further Reading

For more details.

- [Changelog](CHANGELOG.md)
- [Design Desiderata](DESIDERATA.md)

## TODO: packaging

- import design docs here
  - https://docs.google.com/document/d/10HVWuQzCw1Whc-czDChwsWPEZRLfyPS7F-dkjHWsIs4
  - https://docs.google.com/document/d/1J7GBEJUPI3UeftJ4C-w3pbBUzk1pU0Sr6zcXufEi7NI
  - https://docs.google.com/document/d/1SeOO18uqdDtHuB8tZ4-_2sql0Yiaco5J1PWdiu6gmAY
- edit comments down
- rdoc

## Possible Future Directions for the Format

- Float representation.
  - Manifest precision?
  - Limited precision?
  - But somehow do better than just `Float#to_s`!
- Streamability and embedability.
  - Support encoders and decoders which have only fixed-size buffers.
- Portability.
  - Was support for Symbols distinct from Strings too Ruby-esque?
  - Native implementation.
- Error-correction coding.
  - There seem to be little or no "standard" algorithms out there, at
    least not as used by the Ruby community.
