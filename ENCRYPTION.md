# OAK: Encryption-in-OAK

OAK is a serialization and envelope format which encodes simple Ruby
objects as strings.  It bundles together a variety of well-understood
encoding libraries into a succinct self-describing package.

OAK v3 was first described in [OAK: The Object ArKive](DESIGN.md).

Since 2017-09-13, OAK has been used by ALI for volatile caches in
Redis, and for durable Correspondence bodies in S3.

In Q4 2017 I evaluated, then set aside, the possibility of adding
encryption features to OAK.  The motive then was to encrypt our
volatile caches in Redis, for which our hosting provider offers no
encryption-at-rest.  This plan was eventually scrapped because we
decided we didn't need it and because I learned enough about modern
encryption to see that my plan was off track.

In Q3 2018 I am updating and simplifying that plan to to support
encryption of secrets.

Author:
- [jhw@prosperworks.com](mailto:jhw@prosperworks.com)

Advisors:
- [isaac@prosperworks.com](mailto:isaac@prosperworks.com)
- [rrastogi@prosperworks.com](mailto:rrastogi@prosperworks.com)
- [clake@prosperworks.com](mailto:clake@prosperworks.com)

Things get tricky with symmetric encryption. The *identity* of our
encryption keys must be communicated from `OAK.encode` to
`OAK.decode`, but they cannot be explicitly present in the OAK
string itself.

Absent encryption, `OAK.decode` is nice unary pure function on OAK
strings.  But to support decryption, `OAK.decode` cannot *only* look
at the OAK string to effect a decode.  It must also have a
side-channel for secrets.  It degenerates to a binary function which
also must be passed a table of available encryption keys.

In anticipation of key migration, OAK works with a dictionary of
multiple named keys.  `OAK.encode` records the encryption key (if
any) in the OAK string, and `OAK.decode` uses the key to select the
proper secrets from the keychain table.

Furthermore, sound encryption practice with streaming modes demands we
include random noise at the start of each encrypted stream.  Hence,
`OAK.encode` degrades from a pure function to be nondeterministic.

Here's a sneak preview of some OAK encryption:

```
$ export TOE_KEYS=foo,bar                                      # set up a key chain with 1 keys

$ export TOE_KEY_foo=oak_3CNB_3725491808_52_RjFTQTMyX0qAlJNbIK4fwYY0kh5vNKF5mMpHK-ZBZkfFarRjVPxS_ok

$ export TOE_KEY_bar=oak_3CNB_201101230_52_RjFTQTMyXxbYlRcFH8JgiFNZMbnlFTAfUyvJCnXgCESpBmav_Etp_ok

$ echo 'Hello!' | bin/oak.rb --format none                     # OAK_3 with naked interior
oak_3CNN_2640238464_12_F1SU6_Hello!_ok

$ echo 'Hello!' | bin/oak.rb --format none --force-oak-4       # OAK_4 with naked interior sneak preview
oak_4_N25_CN2640238464_F1SU6_Hello!_ok

$ echo 'Hello!' | bin/oak.rb                                   # OAK_3 defaults to base64
oak_3CNB_2640238464_16_RjFTVTZfSGVsbG8h_ok

$ echo 'Hello!' | bin/oak.rb               --force-oak-4       # OAK_4 defaults to base64
oak_4_B34_Q04yNjQwMjM4NDY0X0YxU1U2X0hlbGxvIQ_ok

$ echo 'Hello!' | bin/oak.rb --key-chain TOE --key foo         # OAK_4 encrypted
oak_4foo_B71_HlcPvmphFuA2gj1GsMBFzZuaHT1YMvq7EOcsBIO7DNtxwszsD4M4p-ZuYc5Z7oq2tl12SA0_ok

$ echo 'Hello!' | bin/oak.rb --key-chain TOE --key foo         # OAK_4 encryption is nondeterministic
oak_4foo_B71_TcLpBTydPhfImx7Uorg_EQPPn2q01AHjHZaXCiGimEoJA2nJZB9nhJP9Bt8_Itv7Kvn0kKs_ok

$ echo 'Hello!' | bin/oak.rb --key-chain TOE --key foo | bin/oak.rb --key-chain TOE --mode decode-lines
Hello!
```
Here is a quick parse of some OAK strings:
```
$ echo 'Hello!' | bin/oak.rb --format none                  # OAK_3 with naked interior
oak_3CNN_2640238464_12_F1SU6_Hello!_ok
oak_3                                                       # OAK ver 3
     C                                                      # checksum Crc32
      N                                                     # compression None
       N                                                    # format None
         2640238464                                         # checksum value (F1SU6_Hello!)
                    12                                      # 12 data bytes  (F1SU6_Hello!)
                       F1SU6_Hello!                         # data FRIZZY, 1 UTF-8 str, 6 chars, "Hello!"
                                    ok                      # end of sequence

$ echo 'Hello!' | bin/oak.rb --format none --force-oak-4    # OAK_4 with naked interior
oak_4_N25_CN2640238464_F1SU6_Hello!_ok
oak_4                                                       # OAK ver 4 w/ no encryption key
      N                                                     # format None
       25                                                   # 25 data bytes (CN2640238464_F1SU6_Hello!)
          C                                                 # checksum Crc32
           N                                                # compression None
            2640238464                                      # checksum value
                       F1SU6_Hello!                         # data FRIZZY, 1 UTF-8 str, 6 chars, "Hello!"
                                    ok                      # end of sequence

$ echo 'Hello!' | bin/oak.rb                                # OAK_3 defaults to base64
oak_3CNB_2640238464_16_RjFTVTZfSGVsbG8h_ok
oak_3                                                       # OAK ver 3
     C                                                      # checksum Crc32
      N                                                     # compression None
       B                                                    # format Base64
         2640238464                                         # checksum value (F1SU6_Hello!)
                    16                                      # 16 data bytes
                       RjFTVTZfSGVsbG8h                     # data: base64("F1SU6_Hello!")
                                        ok                  # end of sequence

$ echo 'Hello!' | bin/oak.rb               --force-oak-4    # OAK_4 defaults to base64
oak_4_B34_Q04yNjQwMjM4NDY0X0YxU1U2X0hlbGxvIQ_ok
oak_4                                                       # OAK ver 4 w/ no encryption key
      B                                                     # format Base64
       34                                                   # 34 data bytes Q04u...vxIQ
          Q04yNjQwMjM4NDY0X0YxU1U2X0hlbGxvIQ                # data: base64("CN2640238464_F1SU6_Hello!")
                                             ok             # end of sequence

$ echo 'Hello!' | bin/oak.rb --key-chain TOE --key foo      # OAK_4 encrypted
oak_4foo_B71_HlcPvmphFuA2gj1GsMBFzZuaHT1YMvq7EOcsBIO7DNtxwszsD4M4p-ZuYc5Z7oq2tl12SA0_ok
oak_4foo                                                    # OAK ver 4 encrypted with key "foo"
         B                                                  # format Base64
          71                                                # 71 data bytes HlcP...2SA0
             HlcP...                                        # base64 of encrypted data
```
The header fields are authenticated, even the ones which are presented
in plaintext:
```
oak_4foo_B                                                  # authenticated-but-plaintext part
          71                                                # in-between part
             HlcP...                                        # authenticated-and-plaintext part
```

## OAK Encryption History

* Proposed Q4 2017: [oak-openssl-ciphers](https://github.com/ProsperWorks/ALI/pull/5434 )

    * Initial support for symmetric key encryption. Not integrated or active.

    * Introduced OAK_4 for encryption but preserves read+write for OAK_3.

    * Sought to expose all algorithms supported by OpenSSL::Cipher.

        * By failing to curate algorithms, less-educated users are put in a position of making expert decisions.

        * Neglected differences between modes of operation.

    * Sought to be deterministic.

        * Neglected risks reusing initialization vectors.

    * Did not merge. 

* Proposed Q3 2018: [oak-openssl-ciphers-redux](https://github.com/ProsperWorks/ALI/pull/9335/files)

    * Still introduces OAK_4 for encryption but preserves read+write for OAK_3.

    * Narrows choices to just AES-256-GCM with random IV.

    * Authenticates all headers.

    * Encrypts all headers not required for decryption.

    * Split out into smaller PRs:

        * [oak-openssl-ciphers-redux-part-i](https://github.com/ProsperWorks/ALI/pull/9560)	plan docs

        * [oak-openssl-ciphers-redux-part-ii](https://github.com/ProsperWorks/ALI/pull/9561)	api syntax

        * [oak-openssl-ciphers-redux-part-iii](https://github.com/ProsperWorks/ALI/pull/9562)	corruption tests

        * [oak-openssl-ciphers-redux-part-iv](https://github.com/ProsperWorks/ALI/pull/9563)	main implementation

        * [oak-openssl-ciphers-redux-part-v](https://github.com/ProsperWorks/ALI/pull/9572)	bin/oak.rb cli

## JHW Revisits Encryption-in-OAK 2018-07-15

[oak-openssl-ciphers](https://github.com/ProsperWorks/ALI/pull/5434)
was originally prepared against
[minor_2017_10_mystic](https://github.com/ProsperWorks/ALI/pull/5930)
and presented in Arch Review 2017-09-18.  It never merged because
feedback and further research raised many questions.  In particular,
the IV is much more delicate than I originally understood.

Per expert recommendations, GCM and CBC are the two more viable stream
modes.  Of them, GCM is much more sensitive to accidental IV reuse.
So much so, that GCM is not recommended in the absence of a fully
automated IV management.

_*At ProsperWorks' current level of organization I believe the only
credible option is CBC or GCM with a random IV selected for every
message.*_

Therefore _*encrypted OAK will be nondeterministic in the plaintext*_.
This is a bummer but I see no way to avoid it without compromising
security.

Also, today I see no point in supporting anything other than AES.  All
of AES-128, AES-192, and AES-256 are probably adequate for our needs,
but if we support just AES-256 then we don't have to answer any thorny
questions.  There too much securit downside in letting the caller pick
any old block cipher or mode of operation which is supported by
OpenSSL.  This outweighs any ambition to future-proof OAK by offering
open-ended support.

GCM not only encrypts, but authenticates.  It is an
[AEAD](https://en.wikipedia.org/wiki/Authenticated_encryption) and we
can authenticate all the headers, including those which are
transmitted in plaintext.

Therefore, _*OAK_4 will support only AES-256-GCM with a random IV
selected each time a message is encrypted*_.  OAK_4 keys will be 32
byte random binary strings.  OAK_4 IVs will be 12 byte binary strings
which are encoded into each OAK string.  OAK_4 will use no salt other
than the random IV for each encryption

_*OAK_4 will allow compression within encryption.*_

_*OAK_4 will encrypt all OAK header fields except those which are
necessary to support decryption.*_ Yes, [Kerckhoffs's
Principle](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle),
but also [Precautionary
Principle](https://en.wikipedia.org/wiki/Precautionary_principle).  To
be transmitted plain: the format and version identifiers "oak_4", the
format code (base64 or none), the name of the key used, and the
redundancy check for the *encrypted* message.

OAK_4 will also support authentication via GCM.  "oak_4", the
encryption key name, and the format flag will be authenticated but
transmitted plain.  All the encrypted fields are also authenticated.
We can save space by skipping redundancy flags in encrypted OAK_4
sequences.

## Appendix: Excerpts from Best Practices Research

[https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation) (sentences rearranged some here to group subtopics better)

An initialization vector (IV) or starting variable
(SV)[[5]](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#cite_note-ISO-10116-5)
is a block of bits that is used by several modes to randomize the
encryption and hence to produce distinct ciphertexts even if the same
plaintext is encrypted multiple times, without the need for a slower
re-keying
process.[[6]](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#cite_note-HUANG-6)

An initialization vector has different security requirements than a
key, so the IV usually does not need to be secret. However, in most
cases, it is important that an initialization vector is never reused
under the same key.

For CBC and CFB, reusing an IV leaks some information about the first
block of plaintext, and about any common prefix shared by the two
messages. ...

In CBC mode, the IV must, in addition, be unpredictable at encryption
time; in particular, the (previously) common practice of re-using the
last ciphertext block of a message as the IV for the next message is
insecure (for example, this method was used by SSL 2.0). If an
attacker knows the IV (or the previous block of ciphertext) before he
specifies the next plaintext, he can check his guess about plaintext
of some block that was encrypted with the same key before (this is
known as the TLS CBC IV attack).

For OFB and CTR, reusing an IV completely destroys security.  This can
be seen because both modes effectively create a bitstream that is
XORed with the plaintext, and this bitstream is dependent on the
password and IV only. Reusing a bitstream destroys security

[https://esj.com/Articles/2008/07/01/8-Best-Practices-for-Encryption-Key-Management-and-Data-Security.aspx?Page=2](https://esj.com/Articles/2008/07/01/8-Best-Practices-for-Encryption-Key-Management-and-Data-Security.aspx?Page=2)

* Step 1: Eliminate as much collection and storage of sensitive data
  as possible - if you don't really need it, get rid of it (or never
  collect it in the first place);
* Step 2: Encrypt, hash, or mask the remaining sensitive data at rest
  and in transit.

* Best Practice #1: Decentralize encryption and decryption
* Best Practice #2: Centralize key management with distributed execution
* Best Practice #3: Support multiple encryption standards
* Best Practice #4: Centralize user profiles for authentication and access to keys
* Best Practice #5: Do not require decryption/re-encryption for key rotation or expiration
* Best Practice #6: Keep comprehensive logs and audit trails
* Best Practice #7: Use one solution to support fields, files, and databases
* Best Practice #8: Support third-party integration

[https://cloud.google.com/security/encryption-at-rest/default-encryption/](https://cloud.google.com/security/encryption-at-rest/default-encryption/)

 April 2017

* Google uses several layers of encryption to protect customer data at
  rest in Google Cloud Platform products.

* Google Cloud Platform encrypts customer content stored at rest,
  without any action required from the customer, using one or more
  encryption mechanisms. There are some minor exceptions.

* Data for storage is split into chunks, and each chunk is encrypted
  with a unique data encryption key. These data encryption keys are
  stored with the data, encrypted with ("wrapped" by) key encryption
  keys that are exclusively stored and used inside Google's central
  Key Management Service. Google's Key Management Service is redundant
  and globally distributed.

* Data stored in Google Cloud Platform is encrypted at the storage
  level using either AES256 or AES128.

* Google uses a common cryptographic library, Keyczar, to implement
  encryption consistently across almost all Google Cloud Platform
  products. (The open-sourced version of Keyczar has known security
  issues, and is NOT the version used internally at Google.) Because
  this common library is widely accessible, only a small team of
  cryptographers needs to properly implement and maintain this tightly
  controlled and reviewed code.

* Google uses the Advanced Encryption Standard (AES) algorithm to
  encrypt data at rest. AES is widely used because (1) [both AES256
  and AES128 are recommended by the National Institute of Standards
  and Technology (NIST) for long-term storage
  use](http://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-131Ar1.pdf)
  (as of November 2015), and (2) AES is often included as part of
  customer compliance requirements.

* Data stored across Google Cloud Storage is encrypted at the storage
  level using AES, in [Galois/Counter Mode
  (GCM)](http://csrc.nist.gov/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf)
  in almost all cases. This is implemented in the [BoringSSL
  library](https://boringssl.googlesource.com/boringssl/) that Google
  maintains. This library was forked from OpenSSL for internal use,
  after [many flaws were exposed in
  OpenSSL](https://www.openssl.org/news/vulnerabilities.html). In
  select cases, AES is used in Cipher Block Chaining (CBC) mode with a
  hashed message authentication code (HMAC) for authentication; and
  for some replicated files, AES is used in Counter (CTR) mode with
  HMAC. (Further details on algorithms are provided [later in this
  document](https://cloud.google.com/security/encryption-at-rest/default-encryption/#googles_common_cryptographic_library).)
  In other Google Cloud Platform products, AES is used in a variety of
  modes.

* In addition to the storage system level encryption described above,
  in most cases data is also encrypted at the storage device level,
  with at least AES128 for hard disks (HDD) and AES256 for new solid
  state drives (SSD), using a separate device-level key (which is
  different than the key used to encrypt the data at the storage
  level). As older devices are replaced, solely AES256 will be used
  for device-level encryption.

* At the time of this document's publication, Google uses the
  following encryption algorithms for encryption at rest for DEKs and
  KEKs. These are subject to change as we continue to improve our
  capabilities and security.

    * Symmetric Encryption
        * *AES-GCM (256 bits) (preferred)*
        * AES-CBC
        * AES-CTR (128 and 256 bits)
        * AES-EAX (128 and 256 bits)
    * Symmetric Signatures
        * HMAC-SHA256 (preferred)
        * HMAC-SHA512
        * HMAC-SHA1

[http://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-131Ar1.pdf](http://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-131Ar1.pdf)

NIST Special Publication 800-131A Revision 1

Transitions: Recommendation for Transitioning the Use of Cryptographic Algorithms and Key Lengths

November 2015 

* *The use of AES-128, AES-192, AES-256 and three-key TDEA is acceptable.*

[http://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf](http://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)

NIST Special Publication 800-38D

Recommendation for Block Cipher Modes of Operation: Galois/Counter
Mode (GCM) and GMAC

November, 2007 

* This Recommendation specifies the Galois/Counter Mode (GCM), an
  algorithm for authenticated encryption with associated data, and its
  specialization, GMAC, for generating a message authentication code
  (MAC) on data that is not encrypted. *GCM and GMAC are modes of
  operation for an underlying approved symmetric key block cipher.*

* GCM is constructed from an approved symmetric key block cipher with
  a block size of 128 bits, such as the Advanced Encryption Standard
  (AES) algorithm that is specified in Federal Information Processing
  Standard (FIPS) Pub. 197 [2]. *Thus, GCM is a mode of operation of
  the AES algorithm.*

* ..If the GCM input is restricted to data that is not to be
  encrypted, the resulting specialization of GCM, called GMAC, is
  simply an authentication mode on the input data. In the rest of this
  document, statements about GCM also apply to GMAC.

* *GCM provides stronger authentication assurance than a
   (non-cryptographic) checksum or error detecting code;* in
   particular, GCM can detect both 1) accidental modifications of the
   data and 2) intentional, unauthorized modifications.

* ...The underlying block cipher shall be approved, the block size
  shall be 128 bits, and *the key size shall be at least 128 bits*.

* ...For IVs, it is recommended that implementations restrict support
  to the length of *96 bits, to promote interoperability, efficiency,
  and simplicity of design*.
    * JHW checked 96 == OpenSSL::Cipher.new('aes-256-gcm').random_iv.size * 8
    * JHW checked 96 == OpenSSL::Cipher.new('aes-128-gcm').random_iv.size * 8

* ... *The IVs in GCM must fulfill the following "uniqueness"
  requirement*: The probability that the authenticated encryption
  function ever will be invoked with the same IV and the same key on
  two (or more) distinct sets of input data shall be no greater than
  2^32.

* Compliance with this requirement is crucial to the security of
  GCM. Across all instances of the authenticated encryption function
  with a given key, if even one IV is ever repeated, then the
  implementation may be vulnerable to the forgery attacks that are
  described in Ref [5] and summarized in Appendix A. *In practice,
  this requirement is almost as important as the secrecy of the key. *

[http://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38c.pdf](http://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38c.pdf)

NIST Special Publication 800-38C 

Recommendation for Block Cipher Modes of Operation: The CCM Mode for
Authentication and Confidentiality

May 2004 

[http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)

Amazon EBS encryption handles key management for you. Each newly created volume is encrypted with a unique 256-bit key. Any snapshots of this volume and any subsequent volumes created from those snapshots also share that key. These keys are protected by AWS key management infrastructure, which implements strong logical and physical security controls to prevent unauthorized access. Your data and associated keys are encrypted using the industry standard AES-256 algorithm.

You cannot change the CMK that is associated with an existing snapshot
or encrypted volume. However, you can associate a different CMK during
a snapshot copy operation (including encrypting a copy of an
unencrypted snapshot) and the resulting copied snapshot use the new
CMK.

The AWS overall key management infrastructure is consistent with
National Institute of Standards and Technology (NIST) 800-57
recommendations and uses cryptographic algorithms approved by Federal
Information Processing Standards (FIPS) 140-2.

Each AWS account has a unique master key that is stored separately
from your data, on a system that is surrounded with strong physical
and logical security controls. Each encrypted volume (and its
subsequent snapshots) is encrypted with a unique volume encryption key
that is then encrypted with a region-specific secure master key. The
volume encryption keys are used in memory on the server that hosts
your EC2 instance; they are never stored on disk in plaintext.

[http://docs.aws.amazon.com/AmazonS3/latest/dev/serv-side-encryption.html](http://docs.aws.amazon.com/AmazonS3/latest/dev/serv-side-encryption.html)

You have three mutually exclusive options depending on how you choose
to manage the encryption keys:

* Use Server-Side Encryption with Amazon S3-Managed Keys (SSE-S3) -
  Each object is encrypted with a unique key employing strong
  multi-factor encryption. As an additional safeguard, it encrypts the
  key itself with a master key that it regularly rotates. Amazon S3
  server-side encryption uses one of the strongest block ciphers
  available, 256-bit Advanced Encryption Standard (AES-256), to
  encrypt your data. For more information, see [Protecting Data Using
  Server-Side Encryption with Amazon S3-Managed Encryption Keys
  (SSE-S3)](http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html).

* Use Server-Side Encryption with AWS KMS-Managed Keys (SSE-KMS) -
  Similar to SSE-S3, but with some additional benefits along with some
  additional charges for using this service. There are separate
  permissions for the use of an envelope key (that is, a key that
  protects your data's encryption key) that provides added protection
  against unauthorized access of your objects in S3. SSE-KMS also
  provides you with an audit trail of when your key was used and by
  whom. Additionally, you have the option to create and manage
  encryption keys yourself, or use a default key that is unique to
  you, the service you're using, and the region you're working in. For
  more information, see [Protecting Data Using Server-Side Encryption
  with AWS KMS-Managed Keys
  (SSE-KMS)](http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingKMSEncryption.html).

* Use Server-Side Encryption with Customer-Provided Keys (SSE-C) - You
  manage the encryption keys and Amazon S3 manages the encryption, as
  it writes to disks, and decryption, when you access your
  objects. For more information, see [Protecting Data Using
  Server-Side Encryption with Customer-Provided Encryption Keys
  (SSE-C)](http://docs.aws.amazon.com/AmazonS3/latest/dev/ServerSideEncryptionCustomerKeys.html).

[https://tools.ietf.org/html/rfc5084#section-2](https://tools.ietf.org/html/rfc5084#section-2)

Using AES-CCM and AES-GCM Authenticated Encryption in the Cryptographic Message Syntax (CMS)

November 2007

Status: Proposed Standard

The reuse of an *AES-CCM* or *AES-GCM* nonce/key combination destroys
the security guarantees.  As a result, it can be extremely difficult
to use AES-CCM or AES-GCM securely when using statically configured
keys.  *For safety's sake, implementations MUST use an automated key
management system*.

JHW Note: If we want to avoid building or buying or renting a KMS, we
should hold back from AES-CCM or AES- GCM for now.  AES-CBC is still a
credible choice and even recommended by some.

[https://tools.ietf.org/html/rfc4107](https://tools.ietf.org/html/rfc4107)

Guidelines for Cryptographic Key Management

June 2005

Status: BEST CURRENT PRACTICE

* When symmetric cryptographic mechanisms are used in a protocol, the
  presumption is that automated key management is generally but not
  always needed.  If manual keying is proposed, the burden of proving
  that automated key management is not required falls to the proposer.

* There is not one answer to that question; circumstances differ.  *In
  general, automated key management SHOULD be used.* Occasionally,
  relying on manual key management is reasonable; we propose some
  guidelines for making that judgment.

* Automated key management and manual key management provide very
  different features.

    * In particular, the protocol associated with an automated key management technique will confirm the liveness of the peer, protect against replay, authenticate the source of the short-term session key, associate protocol state information with the short-term session key, and ensure that a fresh short-term session key is generated.

    * For some symmetric cryptographic algorithms, implementations
      must prevent overuse of a given key.  An implementation of such
      algorithms can make use of automated key management when the
      usage limits are nearly exhausted, in order to establish
      replacement keys before the limits are reached, thereby
      maintaining secure communications.

    * Examples of automated key management systems include IPsec IKE
      and Kerberos. S/MIME and TLS also include automated key
      management functions.

* Key management schemes should not be designed by amateurs; it is
  almost certainly inappropriate for working groups to design their
  own.

* In general, automated key management SHOULD be used to establish
  session keys.

* Automated key management MUST be used if any of these conditions hold:

    * A party will have to manage n^2 static keys, where n may become large.

    * Any stream cipher (such as RC4
      [[TK](https://tools.ietf.org/html/rfc4107#ref-TK)], AES-CTR
      [[NIST](https://tools.ietf.org/html/rfc4107#ref-NIST)], or
      AES-CCM [[WHF](https://tools.ietf.org/html/rfc4107#ref-WHF)]) is
      used.

    * An initialization vector (IV) might be reused, especially an
      implicit IV.  Note that random or pseudo-random explicit IVs are
      not a problem unless the probability of repetition is high.

    * Large amounts of data might need to be encrypted in a short
      time, causing frequent change of the short-term session key.

    * Long-term session keys are used by more than two
      parties. Multicast is a necessary exception, but multicast key
      management standards are emerging in order to avoid this in the
      future. Sharing long-term session keys should generally be
      discouraged.

    * The likely operational environment is one where personnel (or device) turnover is frequent, causing frequent change of the short-term session key.

* Manual key management may be a reasonable approach in any of these situations:

    * The environment has very limited available bandwidth or very
      high round-trip times.  Public key systems tend to require long
      messages and lots of computation; symmetric key alternatives,
      such as Kerberos, often require several round trips and
      interaction with third parties.

    * The information being protected has low value.

    * The total volume of traffic over the entire lifetime of the long-term session key will be very low.

    * The scale of each deployment is very limited.

* Note that assertions about such things should often be viewed with
  skepticism. The burden of demonstrating that manual key management
  is appropriate falls to the proponents -- and it is a fairly high
  hurdle.

* Systems that employ manual key management need provisions for key
  changes.  There MUST be some way to indicate which key is in use to
  avoid problems during transition.  Designs SHOULD sketch plausible
  mechanisms for deploying new keys and replacing old ones that might
  have been compromised.  If done well, such mechanisms can later be
  used by an add-on key management scheme.

* Lack of clarity about the parties involved in authentication is not
  a valid reason for avoiding key management.  Rather, it tends to
  indicate a deeper problem with the underlying security model.

* When manual key management is used, long-term shared secrets MUST be
  unpredictable "random" values, ensuring that an adversary will have
  no greater expectation than 50% of finding the value after searching
  half the key search space.

JHW Note: RFC-4107 talks a lot about session keys.  I don't know how
the session concept applies to our encryption at rest use cases, so I
am not sure how to interpret some of this.

[https://tools.ietf.org/html/bcp106](https://tools.ietf.org/html/bcp106)

Randomness Requirements for Security

June 2005

* /dev/random returns bytes from the pool but blocks when the
  estimated entropy drops to zero. As entropy is added to the pool
  from events, more data becomes available via /dev/random.  Random
  data obtained from such a /dev/random device is suitable for key
  generation for long term keys, if enough random bits are in the pool
  or are added in a reasonable amount of time.

    * *Random data obtained from ... /dev/random ... is suitable for
       key generation for long term keys*

* /dev/urandom works like /dev/random; however, it provides data even
  when the entropy estimate for the random pool drops to zero.  This
  may be adequate for session keys or for other key generation tasks
  for which blocking to await more random bits is not acceptable.  The
  risk of continuing to take data even when the pool's entropy
  estimate is small in that past output may be computable from current
  output, provided that an attacker can reverse SHA-1.  Given that
  SHA-1 is designed to be non-invertible, this is a reasonable risk.

    * */dev/urandom ... may be adequate for session keys or for other
       key generation tasks for which blocking to await more random
       bits is not acceptable.*

* To obtain random numbers under Linux, Solaris, or other UNIX systems
  equipped with code as described above, all an application has to do
  is open either /dev/random or /dev/urandom and read the desired
  number of bytes.

[https://www.feistyduck.com/library/openssl-cookbook/online/ch-openssl.html#openssl-recommended-configuration](https://www.feistyduck.com/library/openssl-cookbook/online/ch-openssl.html#openssl-recommended-configuration)

The design principles for all configurations here are essentially the
same as those from the previous section, but I am going to make two
changes to achieve better performance. First, I am going to put
128-bit suites on top of the list. Although 256-bit suites provide
some increase in security, for most sites the increase is not
meaningful and yet still comes with the performance penalty. Second, I
am going to prefer HMAC-SHA over HMAC-SHA256 and HMAC-SHA384
suites. The latter two are much slower but also don't provide a
meaningful increase in security.

...

The following is my default starting configuration, designed to offer
strong security as well as good performance:

- ECDHE-ECDSA-AES128-GCM-SHA256
- ECDHE-ECDSA-AES256-GCM-SHA384
- ECDHE-ECDSA-AES128-SHA
- ECDHE-ECDSA-AES256-SHA
- ECDHE-ECDSA-AES128-SHA256
- ECDHE-ECDSA-AES256-SHA384
- ECDHE-RSA-AES128-GCM-SHA256
- ECDHE-RSA-AES256-GCM-SHA384
- ECDHE-RSA-AES128-SHA
- ECDHE-RSA-AES256-SHA
- ECDHE-RSA-AES128-SHA256
- ECDHE-RSA-AES256-SHA384
- DHE-RSA-AES128-GCM-SHA256
- DHE-RSA-AES256-GCM-SHA384
- DHE-RSA-AES128-SHA
- DHE-RSA-AES256-SHA
- DHE-RSA-AES128-SHA256
- DHE-RSA-AES256-SHA256

JHW Note: ^^^ Of course that recommendation is for a web site, not for
cold storage.

[http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL/Cipher.html](http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL/Cipher.html)

Ruby docs for OpenSSL::Cipher

* You should never use ECB mode unless you are absolutely sure that
  you absolutely need it

* Always create a secure random IV for every encryption of your
  [Cipher](http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL/Cipher/Cipher.html)

* If the
  [OpenSSL](http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL.html)
  version used supports it, an Authenticated Encryption mode (such as
  GCM or CCM) should always be preferred over any unauthenticated
  mode.

* Currently,
  [OpenSSL](http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL.html)
  supports AE only in combination with Associated Data (AEAD) where
  additional associated data is included in the encryption process to
  compute a tag at the end of the encryption. This tag will also be
  used in the decryption process and by verifying its validity, the
  authenticity of a given ciphertext is established.

* This is superior to unauthenticated modes in that it allows to
  detect if somebody effectively changed the ciphertext after it had
  been encrypted. This prevents malicious modifications of the
  ciphertext that could otherwise be exploited to modify ciphertexts
  in ways beneficial to potential attackers.

* If no associated data is needed for encryption and later decryption,
  the
  [OpenSSL](http://ruby-doc.org/stdlib-2.0.0/libdoc/openssl/rdoc/OpenSSL.html)
  library still requires a value to be set - "" may be used in case
  none is available. An example using the GCM (Galois Counter Mode)...

[https://tools.ietf.org/html/rfc4880#page-6](https://tools.ietf.org/html/rfc4880#page-6)

OpenPGP Message Format

November 2007

Status PROPOSED  STANDARD

* OpenPGP wraps it all in Radix-64 aka ASCII Armor.

    * header (e.g. "-----BEGIN PGP MESSAGE-----")

    * armor headers 

    * armored data

    * checksum

    * footer

* To encrypt, OpenPGP generates a new "session key" for each message,
  which is encrypted with the recipient's public key.

    * The encrypted session key is sent with the message.

The (unencrypted) session key is used to symmetrically encrypt the
(usually compressed) message.

* To authenticate, OpenPGP generates a hash of the message, encrypts
  it with the sender's private key.

    * The encrypted message hash is sent with the message.

* OpenPGP implements, and recommends, compress-then-encrypt!

    * "OpenPGP implementations SHOULD compress the message after
      applying the signature but before encryption."

    * "... Furthermore, compression has the added side effect that
      some types of attacks can be thwarted by the fact that slightly
      altered, compressed data rarely uncompresses without severe
      errors.  This is hardly rigorous, but it is operationally
      useful. ..."

* Asymmetric include RSA, Elgamal, DSA.

* Symmetric include plain, IDEA, TripleDES, CAST5, Blowfish, AES-128,
  -192, -256, Twofish

* No IV but super-salty.

    * "OpenPGP CFB mode uses an initialization vector (IV) of all
      zeros, and prefixes the plaintext with BS+2 octets of random
      data, such that octets BS+1 and BS+2 match octets BS-1 and BS.
      It does a CFB resynchronization after encrypting those BS+2
      octets."

* Compression include none, ZIP, ZLIB, BZIP2

* Hashes include MD5, SHA-1, SHA256, SHA512, others

* GnuPG is a compliant implementation.

* OpenPGP is slammed in
  [https://blog.cryptographyengineering.com/2014/08/13/whats-matter-with-pgp/](https://blog.cryptographyengineering.com/2014/08/13/whats-matter-with-pgp/)
  on:

    * Key management

    * Format

    * Defaults

[https://www.apple.com/business/docs/iOS_Security_Guide.pdf](https://www.apple.com/business/docs/iOS_Security_Guide.pdf)

iOS Security

10 March 2017

* When an iOS device is turned on, its application processor
  immediately executes code from read-only memory known as the Boot
  ROM. This immutable code, known as the hardware root of trust, is
  laid down during chip fabrication, and is implicitly trusted. The
  Boot ROM code contains the Apple Root CA public key, which is used
  to verify that the iBoot bootloader is signed by Apple before
  allowing it to load.

* Every iOS device has a dedicated AES 256 crypto engine built into
  the DMA path between the flash storage and main system memory,
  making file encryption highly efficient.

* The device's unique ID (UID) and a device group ID (GID) are AES
  256-bit keys fused (UID) or compiled (GID) into the application
  processor and Secure Enclave during manufacturing. No software or
  firmware can read them directly;

* Additionally, the Secure Enclave's UID and GID can only be used by
  the AES engine dedicated to the Secure Enclave. The UIDs are unique
  to each device and aren't recorded by Apple or any of its suppliers.

* The UID allows data to be cryptographically tied to a particular device. 

* Apart from the UID and GID, all other cryptographic keys are created
  by the system's random number generator (RNG) using an algorithm
  based on CTR_DRBG. System entropy is generated from timing
  variations during boot, and additionally from interrupt timing once
  the device has booted. Keys generated inside the Secure Enclave use
  its true hardware random number.

* *Every time a file on the data partition is created,* Data
   Protection creates *a new 256-bit key* (the "per-file" key) and
   gives it to the hardware AES engine, which uses the key to encrypt
   the file as it *is written to flash memory using AES CBC
   mode*. ... *The initialization vector (IV) is calculated with the
   block offset into the file, encrypted with the SHA-1 hash of the
   per-file key.* The *per-file key is wrapped* with one of several
   class keys, depending on the circumstances under which the file
   should be accessible. Like all other wrappings, this is performed
   *using NIST AES key wrapping, per RFC 3394*. The wrapped per-file
   key is stored in the file's metadata.

* The metadata of all files in the file system is encrypted with a
  random key, which is created when iOS is first installed or when the
  device is wiped by a user.

* ...this key isn't used to maintain the confidentiality of data;
  instead, it's designed to be quickly erased on demand

[https://tools.ietf.org/html/rfc3394](https://tools.ietf.org/html/rfc3394)       

Advanced Encryption Standard (AES) Key Wrap Algorithm

September 2002

* The AES Key Wrap algorithm will probably be adopted by the USA for
  encryption of AES keys.
* NIST has assigned the following object identifiers to identify the
  key wrap algorithm...
    * id-aes128-wrap
    * id-aes192-wrap
    * id-aes256-wrap

[https://tools.ietf.org/html/rfc529](https://tools.ietf.org/html/rfc5297)[7](https://tools.ietf.org/html/rfc5297)

Synthetic Initialization Vector (SIV) Authenticated Encryption          

Using the Advanced Encryption Standard (AES)

October 2008

* The nonce-based authenticated encryption schemes described above are
  susceptible to reuse and/or misuse of the nonce.  Depending on the
  specific scheme there are subtle and critical requirements placed on
  the nonce.

* ... many applications obtain access to cryptographic functions via
  an application program interface to a cryptographic library.

* These libraries are typically not stateful and any nonce,
  initialization vector, or counter required by the cipher mode is
  passed to the cryptographic library by the application.

* Putting the construction of a security-critical datum outside the
  control of the encryption engine places an onerous burden on the
  application writer who may not provide the necessary cryptographic
  hygiene.

* Perhaps his random number generator is not very good or maybe an
  application fault causes a counter to be reset.  The fragility of
  the cipher mode may result in its inadvertent misuse.  Also, if
  one's environment is (knowingly or unknowingly) a virtual machine,
  it may be possible to roll back a virtual state machine and cause
  nonce reuse thereby gutting the security of the authenticated
  encryption scheme.

[https://www.schneier.com/books/cryptography_engineering/](https://www.schneier.com/books/cryptography_engineering/)

Cryptography Engineering: Design Principles and Practical Applications

© 2010 Ferguson, Schneier, Kohno

I cite here the book, not the website.

* Chapter 3, Section 3.5.6, p59

    * "Despite these cryptographic advances, *AES is still what we
      recommend*. It is fast.  All known attacks are theoretical, not
      practical... It is also the official standard, sanctioned by the
      U.S. government."

* Chapter 3, Section 3.5.7, p60

    * "Note that *we advocate the use of 256-bit keys for systems with
      a design strength of 128 bits*."

    * "To emphasize our desire for 128 bits of security, and thus our
      quest for a secure block cipher, *we will use AES with 256-bit
      keys throughout the rest of this book*."  But once there is a
      clear consensus of how to respond to the new cryptanalytic
      results against AES, we will likely replace AWS with another
      block cipher with 256-bit keys."

* Chapter 4, Section 4.5, p70

    * "As with OFB mode, *you must make absolutely sure never to reuse
      a single key/nonce combination*.  This is a disadvantage that is
      often mentioned for CTR, but CBC has exactly the same problem.
      If you use the same IV twice, you start leaking data about the
      plaintexts.  *CBC is a bit more robust, as it is more likely to
      limit the amount of information leaked*."

    * "The real question is whether you can ensure that the nonce is
      unique.  If there's any doubt, *you should use a mode like
      random IV CBC mode, where the IV is generated randomly and
      outside of the application developer's control*.

* Chapter 4, Section 4.7, p71

    * "Nonce generation turns out to be a really hard problem in many
      systems, so we do not recommend exposing to application
      developers any mode that uses nonces. ... so *if you're
      developing an application and need to use an encryption mode,
      play it safe and use random IV CBC mode*.

* Chapter 5, Section 5.5, p87

    * "In the short term, *we recommend using one of the newer SHA
      hash function family members - SHA-224, SHA-256, SHA-385, or
      SHA-512*.  Moreover we suggest you choose a hash function from
      the SHA(sub d) family, or *use SHA-512 and truncate the output
      to 256 bits*.  In the long run, *we will very likely recommend
      the winner of the SHA-3 competition*."

    * JHW Note: [https://en.wikipedia.org/wiki/SHA-3](https://en.wikipedia.org/wiki/SHA-3) SHA-3 released August 5, 2015

* Chapter 6, Introduction, p89

    * "*Encryption* prevents Eve from reading the messages but *does
      not prevent her from manipulating the messages*.  This is where
      the MAC comes in."

* Chapter 6, Section 6.6, p95

    * "As you may have gathered from the previous discussion, *we
      would choose HMAC-SHA-256*: the HMAC construction using SHA-256
      as a hash function.  Most systems use 64- or 96-bit MAC values,
      and even that might seem like a lot of overhead.  As far as we
      know, there is no collision attack on the MAC value if it is
      used in the traditional manner, so *truncating the results from
      HMAC-SHA-256 to 128 bits should be safe*, given current
      knowledge in the field"

    * "GMAC is fast, but provides only at most 64 bits of security and
      isn't suitable when used to produce short tags.  It also
      requires a nonce, which is a common source of security problem
      [sic -jhw]."

* Chapter 6, Section 6.7, p97

    * "This is where the Horton Principle comes in.  *You should
      authenticate the meaning, not the message.* This means that *the
      MAC should authenticate not only _m_, but also all the
      information that Bob uses in parsing _m_ into its meaning*.
      This would typically include data like protocol identifier,
      protocol version number, protocol message identifier, sizes for
      various fields, etc."

    * "The Horton Principle is one of the reasons why *authentication
      at lower protocol levels does not provide adequate
      authentication for higher-level protocols*.  An authentication
      system at the IP packet level cannot know how the e-mail program
      is going to interpret the data.  This precludes it from checking
      that the context in which the message is interpreted is the same
      as the context in which the message was sent.  The only solution
      is to have the e-mail program provide its own authentication of
      the data exchanged - in addition to the authentication on the
      lower levels of course."

