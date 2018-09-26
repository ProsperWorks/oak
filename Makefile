#
# Makefile
#
# "make test" tests the external behavior of cli utilities which are
# not accessible to "rake test".
#
# author: jhw@prosperworks.com
# incept: 2019-09-25
#

.SUFFIXES:
SHELL         := bash
DESTDIR       := build/make
SOURCES       := $(shell find bin lib -type f -name '*.rb')

.PHONY: all
.PHONY: test
all: test

.PHONY: clean
clean:
	rm -rf $(DESTDIR)

# "make test-oak" tests bin/oak.rb for loadability and basic behavior.
#
test test-oak: $(DESTDIR)/bin/oak.rb.ok
$(DESTDIR)/bin/oak.rb.ok: $(SOURCES)
	mkdir -p $(dir $@)
	bin/oak.rb --self-test
	rubydoctest bin/oak.rb
	bin/oak.rb --help
	echo hello | bin/oak.rb | bin/oak.rb --mode decode-lines | diff <(echo hello) -
	cat Makefile | bin/oak.rb --mode encode-file | bin/oak.rb --mode decode-lines | diff Makefile -
	cat Makefile | bin/oak.rb --mode encode-file | bin/oak.rb --mode decode-file | diff Makefile -
	cat Makefile | bin/oak.rb --mode encode-lines | bin/oak.rb --mode decode-lines | diff -w Makefile -
	cat .git/index | bin/oak.rb --mode encode-file | bin/oak.rb --mode decode-file | diff .git/index -
	set -o pipefail ; echo | bin/oak.rb --mode tests > /dev/null
	set -o pipefail ; echo | bin/oak.rb --mode crazy > /dev/null
	touch $@

# This keychain is only used for tests in this Makefile.
#
export ENIGMA_KEYS=foo,bar
export ENIGMA_KEY_foo=oak_3CNB_3725491808_52_RjFTQTMyX0qAlJNbIK4fwYY0kh5vNKF5mMpHK-ZBZkfFarRjVPxS_ok
export ENIGMA_KEY_bar=oak_3CNB_201101230_52_RjFTQTMyXxbYlRcFH8JgiFNZMbnlFTAfUyvJCnXgCESpBmav_Etp_ok

# "make test-encryption" tests the encryption features in bin/oak.rb.
#
.PHONY: test-encryption
test test-encryption: $(DESTDIR)/bin/oak-encryption.ok
$(DESTDIR)/bin/oak-encryption.ok: bin/oak.rb lib/oak.rb
	mkdir -p $(dir $@)
	set -o pipefail ; bin/oak.rb --key-generate | grep '^oak_3[-_0-9a-zA-Z]*_ok$$'
	set -o pipefail ; cat Makefile | bin/oak.rb --mode encode-lines --key-chain ENIGMA --key foo | bin/oak.rb --mode decode-lines --key-chain ENIGMA | diff -w Makefile -
	set -o pipefail ; cat Makefile | bin/oak.rb --mode encode-file --key-chain ENIGMA --key bar | bin/oak.rb --mode decode-file --key-chain ENIGMA | diff Makefile -
	set -o pipefail ; bin/oak.rb --key-check | grep 'no --key-chain specified'
	set -o pipefail ; bin/oak.rb --key-check --key-chain BOGUS_KEY_CHAIN_TEST | grep 'BOGUS_KEY_CHAIN_TEST: no keys found'
	set -o pipefail ; bin/oak.rb --key-check --key-chain ENIGMA | grep 'ENIGMA: found keys: foo bar'
	@echo
	@echo We can recognize which key encrypted which OAK string:
	@echo
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo We can recode one from one key to another
	@echo
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key foo | bin/oak.rb --mode recode-file --key-chain ENIGMA --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo Both are decodeable as the original source:
	@echo
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key foo | bin/oak.rb --key-chain ENIGMA --mode decode-file | diff <(echo Hello) - > /dev/null
	echo Hello | bin/oak.rb --mode encode-file --key-chain ENIGMA --key foo | bin/oak.rb --mode recode-file --key-chain ENIGMA --key bar | bin/oak.rb --key-chain ENIGMA --mode decode-file | diff <(echo Hello) - > /dev/null
	@echo
	@echo bin/oak.rb passed all the encryption tests.
	@echo
	@touch $@

# "make test-enigma" tests bin/enigma.rb for loadability and behavior.
#
.PHONY: test-enigma
test test-enigma: $(DESTDIR)/bin/enigma.rb.ok
$(DESTDIR)/bin/enigma.rb.ok:  $(SOURCES)
	@mkdir -p $(dir $@)
	@echo
	@echo We can generate keys.
	@echo
	bin/enigma.rb --keygen > /dev/null
	bin/enigma.rb --keygen | grep '^oak_3.*_ok$$' > /dev/null
	@echo
	@echo We can inspect keys.
	@echo
	bin/enigma.rb --keyshow > /dev/null
	bin/enigma.rb --keyshow | grep '^foo bar$$' > /dev/null
	env ENIGMA_KEYS=bar bin/enigma.rb --keyshow | grep '^bar$$' > /dev/null
	env ENIGMA_KEYS=bar,foo bin/enigma.rb --keyshow | grep '^bar foo$$' > /dev/null
	@echo
	@echo We can encode secrets with the default key.
	@echo
	echo Hello | bin/enigma.rb --encrypt | grep '^oak_4foo' > /dev/null
	echo Hello | env ENIGMA_KEYS=bar,foo bin/enigma.rb --encrypt | grep '^oak_4bar' > /dev/null
	@echo
	@echo We can decode secrets and recover them.
	@echo
	echo Hello | bin/enigma.rb --encrypt | bin/enigma.rb --decrypt | grep '^Hello$$' > /dev/null
	diff Makefile <(cat Makefile | bin/enigma.rb --encrypt | bin/enigma.rb --decrypt) > /dev/null
	@echo
	@echo Multi-line inputs are encrypted as one line of OAK.
	@echo
	diff -w <(echo '1')     <(cat Makefile | bin/enigma.rb --encrypt | wc -l)
	@echo
	@echo Multi-line inputs are recoverable.
	@echo
	diff    Makefile        <(cat Makefile | bin/enigma.rb --encrypt | bin/enigma.rb --decrypt)
	@echo
	@echo Only the first line of a multi-line input is decrypted.
	@echo
	@echo The idea is that --decrypt reverses --encrypt, and
	@echo --encrypt only produces a single OAK string.
	@echo
	diff -w <(echo '2')     <(echo -e 'Hello\nGoodbye' | wc -l)
	diff -w <(echo '2')     <(echo -e 'Hello\nGoodbye' | bin/oak.rb --mode encode-lines | wc -l)
	diff    <(echo 'Hello') <(echo -e 'Hello\nGoodbye' | bin/oak.rb --mode encode-lines | bin/enigma.rb --decrypt)
	diff    <(echo 'Hello') <(echo -e 'oak_3CNB_2988590367_15_RjFTVTVfSGVsbG8_ok\noak_3CNB_3136943697_18_RjFTVTdfR29vZGJ5ZQ_ok' | bin/enigma.rb --decrypt)
	@echo
	@echo Encoded secrets are nondeterministic.
	@echo
	! diff <(echo Hello | bin/enigma.rb --encrypt) <(echo Hello | bin/enigma.rb --encrypt) > /dev/null
	@echo
	@echo We can recode one from one key to another
	@echo
	echo Hello | bin/enigma.rb --encrypt | grep '^oak_4foo' > /dev/null
	echo Hello | bin/enigma.rb --encrypt | env ENIGMA_KEYS=bar,foo bin/enigma.rb --recrypt | grep '^oak_4bar' > /dev/null
	diff Makefile <(cat Makefile | bin/enigma.rb --encrypt | env ENIGMA_KEYS=bar,foo bin/enigma.rb --recrypt | bin/enigma.rb --decrypt)
	@echo
	@echo bin/enigma.rb is picky.
	@echo
	! bin/enigma.rb --bogus-garbage-parameter
	@echo
	@echo bin/enigma.rb is friendly.
	@echo
	bin/enigma.rb --help > /dev/null
	bin/enigma.rb        > /dev/null
	diff <(bin/enigma.rb --help) <(bin/enigma.rb)
	@echo
	@echo bin/enigma.rb passed all tests.
	@echo
	@touch $@
