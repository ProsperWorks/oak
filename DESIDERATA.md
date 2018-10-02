# oak design desiderata

Some design goals with which I started this project.

- P1 means "top priorty"
- P2 means "very important"
- P3 means "nice to have"
- P4 means "not harmful if cheap"

- `+` means "accomplished"
- `-` means "not accomplished"
- `?` means "accomplished, but only for some combinations of arguments"

Desiderata for the structure layer:

- P1 + losslessly handle nil, true, false, Integer, and String
- P1 + losslessly handle List with arbitrary values and deep nesting
- P1 + losslessly handle Hash with string keys and deep nesting in values
- P1 + detect cycles and DAGS in input structures, fail or handle
- P1 + handle all Integer types without loss
- P1 - handle Floats with no more than a small quantified loss
- P2 + Hash key ordering is preserved in Ruby-Ruby transcoding
- P3 - convenient:  vaguely human-readable representations available
- P3 + encode cycles and DAGs
- P3 + handle Hash with non-string keys and deep nesting in keys
- P3 + losslessly handle Symbol distinct from String
- P3 - handle Times and Dates

Desiderata for the byte layer:

- P1 + reversible:  original string can be reconstructed from only OAK string
- P1 + unambiguous: no OAK string is the prefix of any other OAK string
- P1 + extensible:  OAK strings contain ids for ver, format, compression, etc
- P1 + robust:      error detection in OAK strings
- P2 + flexible:    multiple compression modes available
- P3 + convenient:  available representation without `{}`, comma, whitespace
- P3 + convenient:  7-bit clean representations available
- P3 + convenient:  representations which are selectable with double-click
- P3 + convenient:  vaguely human-readable representations available
- P3 - streamable:  reversing can be accomplished with definite-size buffers
- P4 - embeddable:  reversing can be accomplished with fixed-size buffers
- P4 - defensive:   error correction available (no good libs found)

Techniques used in the byte layer to accomplish these goals.

- manifest type id for self-identification
- manifest version id in case format changes in future
- salient encoding algorithm choices stored in output stream
  - error detection algorithm aka redundancy
  - compression
  - formatting
- microchoices made to confine metadata characters to [_0-9a-z]
- algorithm menu constructed to offer data characters in [-_0-9a-z]


## Serialization Choices

A survey of alternatives considered for the serialization layer.

### Considering Marshal

The Marshal format has some major drawbacks which I believe make it
a nonstarter.

- strictly Ruby-specific
- readability across major versions not guaranteed
- too powerful: can be used to execute arbitrary code
- binary and non-human-readable
  - many option combos for oak make oak strings also non-human-readable
  - still, it is nice to have layer which is at least potentially clear

Marshal does offer one major advantage:

- transcodes all Ruby value types and user-defined value-like classes
- reported to be much faster than JSON or YAML for serializing

### Considering JSON

JSON is awesome most of the time, especially in highly constrained
environments such as API specifications and simple ad-hoc caching
situations.

JSON offers advantages:

- a portable object model
- easy to read
- widely deployed
- the go-to choice for interchange in recent years

But it has some shortcomings which lead me to reject it for the
structural level in OAK.

- floating point precision is implementation-dependent
- always decodes as a tree - fails to transcode DAGiness
- cannot represent cycles - encoder reject, stack overflow, or infinite loop
- no native date or time handling
- table keys may only be strings
  - e.g. `{'123'=>'x'} == JSON.parse(JSON.dump({123=>'x'}))`
- type information symbol-vs-string lost, symbols transcode to strings
  - e.g. `'foo'        == JSON.parse(JSON.dump(:foo))`
  - e.g. `{'foo'=>'x'} == JSON.parse(JSON.dump({:foo=>'x'}))`
- official grammer only allows {} or [] as top-level object
  - e.g. `123 == JSON.parse('123')` but `JSON.parse('123')` raises `ParserError`
  - many parsers in the wild support only this strict official grammer
  - JSON is suitable only for document encoding, not streams
    - allows only one object per file
    - multiple objects must be members of a list
    - lists must be fully scanned and parsed before being processed
    - no possibility of streamy processing

Biggest limitation of JSON IMO is that Hash keys can only be strings:
```
2.1.6 :008 > obj = {'str'=>'bar',[1,2,3]=>'baz'}
 => {"str"=>"bar", [1, 2, 3]=>"baz"}
2.1.6 :009 > JSON.dump(obj)
 => "{\"str\":\"bar\",\"[1, 2, 3]\":\"baz\"}"
2.1.6 :010 > JSON.parse(JSON.dump(obj))
 => {"str"=>"bar", "[1, 2, 3]"=>"baz"}
2.1.6 :011 > JSON.parse(JSON.dump(obj)) == obj
 => false
```

### Considering YAML

YAML is strong where JSON is strong, and also strong in many places
where JSON is weak.  In fact, YAML includes JSON as a subformat: JSON
strings *are* YAML strings!

Some of the advantages of YAML over JSON are:

- handles any directed graph, including DAGy bits and cycles
- arguably more human-readable than JSON
- YAML spec subsumes JSON spec: JSON files are YAML files
- supports non-string keys
  - e.g. `{123=>'x'}  == YAML.load(YAML.dump({123=>'x'}))`
- supports symbols
  - e.g. `:foo        == YAML.load(YAML.dump(:foo))`
  - e.g. `{:foo=>'x'} == YAML.load(YAML.dump({:foo=>'x'}))`
- allows integer or string as top-level object

YAML overcomes the biggest limitation of JSON by supporting non-string
hash keys:
```
  2.1.6 :008 > obj = {'str'=>'bar',[1,2,3]=>'baz'}
   => {"str"=>"bar", [1, 2, 3]=>"baz"}
  2.1.6 :012 > YAML.dump(obj)
   => "---\nstr: bar\n? - 1\n  - 2\n  - 3\n: baz\n"
  2.1.6 :013 > YAML.load(YAML.dump(obj))
  => {"str"=>"bar", [1, 2, 3]=>"baz"}
  2.1.6 :014 > YAML.load(YAML.dump(obj)) == obj
   => true
```

Note: YAML's support for Symbols is due to Psych, not strictly the
YAML format itself.  I've taken both `YAML.dump(:foo)` and
`YAML.dump(':foo')` into Python and done `yaml.load()` on them.  Both
result in `':foo'`.  So this nicety is not portable.

But YAML still has some shortcomings:

- floating point precision is implementation-dependent
- no native date or time handling
- unclear whether available parsers support stream processing
- DAGs and cycles of Arrays and Hash are handled, but Strings are not.

### Considering FRIZZY

FRIZZY is a home-grown serialization format which I ended up commiting
to for OAK.

The name FRIZZY means nothing, and survives only as the rogue `F`
character at the start of a serialized object:

```
.1.6 :006 > OAK.encode('Hello, World!',redundancy: :none,format: :none)
 => "oak_3NNN_0_20_F1SU13_Hello, World!_ok"
```

Advantages:

  - Recongizes when Strings are identical, not just equivalent.
  - It is much more compact than YAML.
  - Has built-in folding of String and Symbol representation.

Disadvantages:

  - Home grown.
  - Very much not human readable.
  - Floating point precision is incompletely specified.
    - Current implementation crudely uses Number.to_s and String.to_f

I decided to reinvent the wheel and go with FRIZZY.  We have
discovered Summaries which are DAGs on strings.  It might be
acceptable to lose that information but I did not want to *prove* it
was acceptable to lose that information.

It may have been an ego-driven sin to go custom here, but I did not
want to pessimize future use cases on fidelity or control.


## Compression Choices

A survey of alternatives considered for the compression layer.

### Considering LZO, LZF, and LZ4.

These compression formats are similar in performance and algorithm.
All are in the Lempel-Ziv family of dictionary-based
redundancy-eaters.  They will all be cheap to compress, cheap to
uncompress, but will delver only modest compression ratios.

This family of algorithms are unfamiliar to those accustomed to
archive formats, but they are used widely in low-latency applications
(such as server caches ;) ).

To keep things simple, I settled on supporting only LZ4 because its
gem, `lz4-ruby`, seems to have more mindshare and momentum.  It is
weaker but faster than the other weak+fast options - which seems like
the way to be.

Based on previous experience, I expect this to be a clear win for use
in Redis caches vs being uncompressed.

### Considering ZLIB

Including ZLIB felt like a no-brainer.  ZLIB is familiar,
widely-deployed, and standardized in RFC 1951.  It uses the L-Z
process with an additional Huffman encoding phase.  It will deliver
intermediate cost for intermediate compression.

Based on previous experience, I expect this option will usually be
dominated by either LZ4 for low-latency applications or BZIP2 for
archival applications, but I'm including it for comparisons and
because it would feel strage not to.

### Considering BZIP2

BZIP2 is an aggressive compression which uses the Burrows–Wheeler,
move-to-front, and run-length-encoding transforms with Huffman It will
be several times slower but several 10% stronger than ZLIB.  I chose
the gem bzip2-ffi over the more flexible rbzip2 to make absolutely
certain that we use the native libbz2 implementation and do not
falling back silently to a Ruby version which is 100x slower if/when
Heroku does not offer FFI.

Based on previous experience, I expect this option will dominate where
data is generally cold or where storage is very expensive compared to
CPU.

### Considering LZMA

LZMA is the Lempel-Ziv-Markov chains algorithm.  It will be an order
of magnitude more expensive to compress than BZIP2, but will
decompress slightly faster and will yield better compression ratios by
few 5%.

This will be useful only for cases where read-write ratios are over 10
and storage:cpu cost ratios are high.  When read-write ratios are
close to unity, LZO will dominate where storage:cpu is low and BZIP2
will dominate where storage:cpu is high.

Nonetheless, I have a soft spot in my heart for this algorithm so I am
including it - if only so we can rule it out by demonstration rather
than hypothesis.


## Encryption Choices

OAK has been live in `ALI` (copper.com's primary web service) in our
Redis cache layer on 2016-06-02 and for archiving correspondence
bodies in S3 on 2016-07-06.

There had been only Rubocop updates and nary a bugfix since
2016-07-01.

Encryption is the first extension since OAK first went live.


### Encryption-in-OAK Design Decisions (see arch doc for discussion):

- Encryption is the only change in OAK4.
- OAK4 will only support AES-256-GCM with random IVs chosen for
  each encryption event.
  - OAK4 will use no salt other than the random IV.
- Encrypted OAK strings will be nondeterministic.
  - This crushes the desiderata of making OAK.encode a pure function.
  - This is unavoidable to avoid a blatant security hole.
- OAK4 dramatically changes how headers are managed from OAK3.
  - Encrypts all headers which are not required for decryption.
  - Athenticates all headers and the encrypted stream.
- Key rotation is supported.
  - Via an ENV-specified key chain.
  - Can hold multiple master keys.

### Encryption-in-OAK Backward Compatibility

Before encryption was added, the format identifier for OAK strings
was `'oak_3'`.

To indicate we are making a non-backward compatible change, I am
bumping that up to `'oak_4'` for encrypted strings.

The legacy OAK3 are still supported both on read and on write.

By default, OAK4 is used only when encryption is requested.

### Encryption-in-OAK Regarding Compression vs Encryption

Note that compression of encrypted strings is next to useless.  By
design, encryption algorithms obscure exploitable redundancy in
plaintext and produce incompressible ciphertext.

On the other hand, in the wild there have been a handful of successful
chosen-plaintext attacks on compress-then-encrypt encodings.  See:

- https://blog.appcanary.com/2016/encrypt-or-compress.html
- https://en.wikipedia.org/wiki/CRIME

OAK4 supports compression and does compression-then-encryption.

The extremely paranoid are encouraged to use compression: :none.  Note
however that the source data may be compressed.  Furthermore, for
larger objects FRIZZY itself is, in part, a compression algorithm.
