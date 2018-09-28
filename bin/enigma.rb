#!/usr/bin/env ruby
#
# bin/enigma.rb
#
# author: jhw@prosperworks.com
# incept: 2018-08-02
#

require_relative '../lib/oak.rb'
require          'optimist'

OPTS        = Optimist.options do
  banner "#{$0} cli driver for wrapping secrets with OAK encryption"
  banner <<-OPTIMIST_EXAMPLES

  Limited, but safe CLI driver for OAK.  Focused on wrapping secrets.

  Supports the right way, does not support the wrong way.  Does not
  leave extra rope lying around, making it difficult to hang yourself.

  Hard-coded to look in the keychain at ENIGMA_KEYS.

Examples:

  $ bin/enigma.rb --keyshow

  $ bin/enigma.rb --keygen
  oak_3CNB_3737590342_52_RjFTQTMyX4WnUcz0rMSRpiPaCREGZ5Ds_X4x9sElnzwYzZ30V8IM_ok
  $ export ENIGMA_KEYS=foo,bar ENIGMA_KEY_foo=$(bin/enigma.rb --keygen) ENIGMA_KEY_bar=$(bin/enigma.rb --keygen)
  $ bin/enigma.rb --keyshow
  foo bar
  $ echo Hello | bin/enigma.rb --encrypt
  oak_4foo_B59_IY-hCMHbVtcjNV1NCfhPBMsh9iRs3062O0102yFplNSklwntZTmJ8_NQ5yo_ok
  $ echo Hello | bin/enigma.rb --encrypt
  oak_4foo_B59_Yvae5FQqqLk8pK6GAh28-zqBlfGaM4qtNk8n-Wk-VZ-l73pGxSzz6CYodlo_ok
  $ echo Hello | bin/enigma.rb --encrypt | bin/enigma.rb --decrypt
  Hello
  $ echo Hello | bin/enigma.rb --encrypt | env ENIGMA_KEYS=bar,foo bin/enigma.rb --recrypt
  oak_4bar_B59_DdFn7X3SfK5bC0tUtSGfSuFJq2E7V7ryhhoDKotjTEuVOPuqrb7cy-dRboU_ok
OPTIMIST_EXAMPLES
  banner ""
  banner "Options:"
  banner ""
  version "#{$0} #{OAK::VERSION}"
  opt(
    :decrypt,
    'decrypt OAK using ENIGMA_KEYS to decrypt',
    :default => false,
  )
  opt(
    :encrypt,
    'encrypt using first key in ENIGMA_KEYS, emits encrypted OAK',
    :default => false,
  )
  opt(
    :recrypt,
    'decrypt, then encrypt using first key in ENIGMA_KEYS, emits encrypted OAK',
    :default => false,
  )
  opt(
    :keygen,
    'generate a random key, emits *un*encrypted OAK',
    :default => false,
  )
  opt(
    :keyshow,
    'show the available keys in the ENIGMA keychain',
    :default => false,
  )
  opt(
    :help,
    'show this help',
  )
end

if __FILE__ == $0
  if OPTS[:keygen]
    key = OAK.random_key
    oak = OAK.encode(key)            # not encrypted: for use in keychains!
    puts oak
    exit 0
  end
  key_chain   = nil
  begin
    key_chain = OAK.parse_env_chain(ENV,'ENIGMA')
  rescue => ex
    puts "failed to parse ENIGMA keychain: #{ex.class} #{ex.message}"
    exit 1
  end
  if OPTS[:decrypt]
    oak = ARGF.read
    raw = OAK.decode(oak,key_chain: key_chain)
    puts raw
    exit 0
  end
  default_key = key_chain.keys.keys.first
  if OPTS[:keyshow]
    puts key_chain.keys.keys.join(' ')
    exit 0
  end
  if !default_key
    Optimist.die "no default key found in ENIGMA_KEYS: #{ENV['ENIGMA_KEYS']}"
  end
  if OPTS[:encrypt] || OPTS[:recrypt]
    raw = ARGF.read
    raw = OAK.decode(raw,key_chain: key_chain) if OPTS[:recrypt]
    oak = OAK.encode(
      raw,
      key_chain:   key_chain,
      key:         default_key,
      redundancy:  :none,       # redundant with AES-256-GCM authentication
      compression: :bzip2,      # encrypt 1x, deploy 100x, decrypt 1000000x
    )
    Optimist.die "oak not oak_4"     if /^oak_4/  !~ oak
    Optimist.die "oak not encrypted" if /^oak_4_/ =~ oak
    puts oak
    exit 0
  end
  Optimist.educate
end
