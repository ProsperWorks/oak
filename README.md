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

## Using in Ruby for Encryption

```
2.1.6 :001 > require 'oak'
 => true
2.1.6 :002 > key_chain = OAK::KeyChain.new({ 'a' => OAK::Key.new(OAK.random_key), 'b' => OAK::Key.new(OAK.random_key) })
 => #<OAK::KeyChain:0x007faa700b8458 @keys={"a"=>#<OAK::Key:0x007faa700b89a8 @key=ELIDED>, "b"=>#<OAK::Key:0x007faa700b86d8 @key=ELIDED>}>
2.1.6 :003 > OAK.encode("Hello, World!",key_chain: key_chain, key: 'a')
 => "oak_4a_B82_4iauuiFq7XQvcDCwmmXhDxL_Wp3_T765qM-S094uNJ4xtj_DxQuXGSMmqlcxPXz-_cYZdE6bFbEAQCHpiQ_ok"
2.1.6 :004 > OAK.encode("Hello, World!",key_chain: key_chain, key: 'a')
 => "oak_4a_B82_YeeAEOLPlGchlDkoSnif7G38uJAPaNQ2ozsx6Mcb7PybpsL-ljVmGa5sRbgaqFw4R5iOXNw_sOesolTB4g_ok"
2.1.6 :005 > OAK.encode("Hello, World!",key_chain: key_chain, key: 'b')
 => "oak_4b_B82_HA1O3v5UrpV81UC0fAaUQ_8tsLUxbMG6bMupcQaZNKMU3XL3Tz9zj8TaVb4nvv3s0UhxFg3q9lmFIplvnQ_ok"
2.1.6 :006 > OAK.decode("oak_4b_B82_HA1O3v5UrpV81UC0fAaUQ_8tsLUxbMG6bMupcQaZNKMU3XL3Tz9zj8TaVb4nvv3s0UhxFg3q9lmFIplvnQ_ok",key_chain: key_chain)
 => "Hello, World!
2.1.6 :007 > OAK.decode("oak_4b_B82_HA1O3v5UrpV81UC0fAaUQ_8tsLUxbMG6bMupcQaZNKMU3XL3Tz9zj8TaVb4nvv3s0UhxFg3q9lmFIplvnQ_ok")
OAK::CantTouchThisStringError: key b but no key_chain
        from ...
```

## Using in Shell

Non-encrypted OAK default to OAK3.  Unencrypted OAK4 is available
optionally.  They are generally the same size and equivalent:
unencrypted OAK4 is generally only used for debugging and getting a
peek at what happens "under the encryption".

```
$ echo hello | bin/oak --mode encode-file
oak_3CNB_911092726_16_RjFTVTZfaGVsbG8K_ok
$ echo oak_3CNB_911092726_16_RjFTVTZfaGVsbG8K_ok | bin/oak --mode decode-file
hello
$ echo hello | bin/oak --mode encode-file --compression lz4 --force true
oak_3C4B_911092726_19_DMBGMVNVNl9oZWxsbwo_ok
$ echo oak_3C4B_911092726_19_DMBGMVNVNl9oZWxsbwo_ok | bin/oak --mode decode-file
hello
$ echo hello | bin/oak.rb --mode encode-lines --redundancy none --format none
oak_3NNN_0_11_F1SU5_hello_ok
$ echo hello | bin/oak.rb --mode encode-lines --redundancy none --format none --force-oak-4
oak_4_N15_NN0_F1SU5_hello_ok
```

## Using in Shell for Encryption

Encryption is supported by OAK4.

```
$ bin/oak.rb --key-generate
oak_3CNB_2975186575_52_RjFTQTMyX00du8vD8WAikhLNgdnaOYtQV6uqyNqRz6modiEcJHOl_ok
$ bin/oak.rb --key-generate
oak_3CNB_1324948677_52_RjFTQTMyXytCueDDTpEOusKkPMANgaA9zsJuvOend5DCIJWwJdjC_ok
$ export OAK_TEST_KEYS=foo,bar
$ export OAK_TEST_KEY_foo=oak_3CNB_2975186575_52_RjFTQTMyX00du8vD8WAikhLNgdnaOYtQV6uqyNqRz6modiEcJHOl_ok
$ export OAK_TEST_KEY_bar=oak_3CNB_1324948677_52_RjFTQTMyXytCueDDTpEOusKkPMANgaA9zsJuvOend5DCIJWwJdjC_ok
$ echo hello | bin/oak.rb --mode encode-lines --redundancy none --key-chain OAK_TEST --key foo
oak_4foo_B58_PhG1qWHfosOOWDgqMhVoZlEn6F16XC6KuL_1zN1aLWMmcZZgJ2Dz5XR-ag_ok
$ echo hello | bin/oak.rb --mode encode-lines --redundancy none --key-chain OAK_TEST --key foo
oak_4foo_B58_ms11iWDHrmwFJwGpNEsWMIXYfapO96e7yvfk5r8G-F1gRzt62FS_JFQbvw_ok
$ echo hello | bin/oak.rb --mode encode-lines --redundancy none --key-chain OAK_TEST --key bar
oak_4bar_B58_kV6FIE30v6xgdKwyzdmpxVzNCU2eWjt7ZiZTWUHsQxXG3cC8u0-VoE0hmQ_ok
$ echo oak_4foo_B58_PhG1qWHfosOOWDgqMhVoZlEn6F16XC6KuL_1zN1aLWMmcZZgJ2Dz5XR-ag_ok | bin/oak.rb --mode decode-lines --key-chain OAK_TEST
hello
$ echo oak_4foo_B58_ms11iWDHrmwFJwGpNEsWMIXYfapO96e7yvfk5r8G-F1gRzt62FS_JFQbvw_ok | bin/oak.rb --mode decode-lines --key-chain OAK_TEST
hello
$ echo oak_4bar_B58_kV6FIE30v6xgdKwyzdmpxVzNCU2eWjt7ZiZTWUHsQxXG3cC8u0-VoE0hmQ_ok | bin/oak.rb --mode decode-lines --key-chain OAK_TEST
hello
```
OAK4 supports one and only one encryption algorithm and mode of
operation:

- AES-256-GCM
  - 128 bits of security
  - 256-bit keys      (32 bytes)
  -  96-bit IVs       (12 bytes)
  - 128-bit auth_tags (16 bytes)
- Random IV ("Initialization Vector") used for each encryption operation.
- All headers are authenticated.
- All headers which are not required for decryption are encrypted.

This is the only encryption option supported by OAK4.

Because the GCM ([Galois/Counter Mode
](https://en.wikipedia.org/wiki/Galois%2FCounter_Mode)) mode of
operation is an [authenticated
encryption](https://en.wikipedia.org/wiki/Authenticated_encryption),
use of `--redundancy none` with encrypted OAK strings is recommended.
The authentication of GCM is more than adequate to detect accidental
transmission errors.  This recommendation may become the default in a
future version.


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
