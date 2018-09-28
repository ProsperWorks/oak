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
DESTDIR       := build

SOURCES       := $(shell find . -type f -name '*.rb')
SOURCES       += $(shell find . -type f -name 'Gemfile*')
SOURCES       += $(shell find . -type f -name 'Rakefile')
SOURCES       += $(shell find . -type f -name '.rubocop.yml')

.PHONY: all
.PHONY: test
all: test

.PHONY: clean
clean:
	rm -rf $(DESTDIR)

# "make test-rake" performs our traditional Ruby Minitest suite.
#
.PHONY: test-rake
test test-rake: $(DESTDIR)/test-rake.ok
$(DESTDIR)/test-rake.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	bundle exec rake test
	@touch $@

# "make test-shell-basic" tests bin/oak.rb for loadability and basic behavior.
#
.PHONY: test-shell-basic
test test-shell-basic: $(DESTDIR)/test-shell-basic.ok
$(DESTDIR)/test-shell-basic.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	@echo
	@echo bin/oak is friendly and self-tests
	@echo
	bin/oak --self-test
	rubydoctest bin/oak.rb
	bin/oak --help
	@echo
	@echo bin/oak can decode its own output in some common cases.
	@echo
	set -o pipefail ; echo hello | bin/oak | bin/oak --mode decode-lines | diff <(echo hello) -
	set -o pipefail ; cat Makefile | bin/oak --mode encode-file | bin/oak --mode decode-lines | diff Makefile -
	set -o pipefail ; cat Makefile | bin/oak --mode encode-file | bin/oak --mode decode-file | diff Makefile -
	set -o pipefail ; cat Makefile | bin/oak --mode encode-lines | bin/oak --mode decode-lines | diff -w Makefile -
	set -o pipefail ; cat .git/index | bin/oak --mode encode-file | bin/oak --mode decode-file | diff .git/index -
	@echo
	@echo bin/oak has some kind of pointless crufty modes, too.
	@echo
	set -o pipefail ; echo | bin/oak --mode tests > /dev/null
	set -o pipefail ; echo | bin/oak --mode crazy > /dev/null
	@echo
	@echo bin/oak passed all the basic tests.
	@echo
	@touch $@

# This keychain is only used for tests in this Makefile.
#
export ENIGMA_KEYS=foo,bar
export ENIGMA_KEY_foo=oak_3CNB_3725491808_52_RjFTQTMyX0qAlJNbIK4fwYY0kh5vNKF5mMpHK-ZBZkfFarRjVPxS_ok
export ENIGMA_KEY_bar=oak_3CNB_201101230_52_RjFTQTMyXxbYlRcFH8JgiFNZMbnlFTAfUyvJCnXgCESpBmav_Etp_ok

# "make test-shell-encryption" tests the encryption features in bin/oak.
#
.PHONY: test-shell-encryption
test test-shell-encryption: $(DESTDIR)/test-shell-encryption.ok
$(DESTDIR)/test-shell-encryption.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	set -o pipefail ; bin/oak --key-generate | grep '^oak_3[-_0-9a-zA-Z]*_ok$$'
	set -o pipefail ; cat Makefile | bin/oak --mode encode-lines --key-chain ENIGMA --key foo | bin/oak --mode decode-lines --key-chain ENIGMA | diff -w Makefile -
	set -o pipefail ; cat Makefile | bin/oak --mode encode-file --key-chain ENIGMA --key bar | bin/oak --mode decode-file --key-chain ENIGMA | diff Makefile -
	set -o pipefail ; bin/oak --key-check | grep 'no --key-chain specified'
	set -o pipefail ; bin/oak --key-check --key-chain BOGUS_KEY_CHAIN_TEST | grep 'BOGUS_KEY_CHAIN_TEST: no keys found'
	set -o pipefail ; bin/oak --key-check --key-chain ENIGMA | grep 'ENIGMA: found keys: foo bar'
	@echo
	@echo We can recognize which key encrypted which OAK string:
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo We can recode one from one key to another
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key foo | bin/oak --mode recode-file --key-chain ENIGMA --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo Both are decodeable as the original source:
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key foo | bin/oak --key-chain ENIGMA --mode decode-file | diff <(echo Hello) - > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain ENIGMA --key foo | bin/oak --mode recode-file --key-chain ENIGMA --key bar | bin/oak --key-chain ENIGMA --mode decode-file | diff <(echo Hello) - > /dev/null
	@echo
	@echo bin/oak passed all the encryption tests.
	@echo
	@touch $@

# "make test-shell-enigma" tests bin/enigma for loadability and behavior.
#
.PHONY: test-shell-enigma
test test-shell-enigma: $(DESTDIR)/test-shell-enigma.ok
$(DESTDIR)/test-shell-enigma.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	@echo
	@echo We can generate keys.
	@echo
	bin/enigma --keygen > /dev/null
	bin/enigma --keygen | grep '^oak_3.*_ok$$' > /dev/null
	@echo
	@echo We can inspect keys.
	@echo
	bin/enigma --keyshow > /dev/null
	bin/enigma --keyshow | grep '^foo bar$$' > /dev/null
	env ENIGMA_KEYS=bar bin/enigma --keyshow | grep '^bar$$' > /dev/null
	env ENIGMA_KEYS=bar,foo bin/enigma --keyshow | grep '^bar foo$$' > /dev/null
	@echo
	@echo We can encode secrets with the default key.
	@echo
	echo Hello | bin/enigma --encrypt | grep '^oak_4foo' > /dev/null
	echo Hello | env ENIGMA_KEYS=bar,foo bin/enigma --encrypt | grep '^oak_4bar' > /dev/null
	@echo
	@echo We can decode secrets and recover them.
	@echo
	echo Hello | bin/enigma --encrypt | bin/enigma --decrypt | grep '^Hello$$' > /dev/null
	diff Makefile <(cat Makefile | bin/enigma --encrypt | bin/enigma --decrypt) > /dev/null
	@echo
	@echo Multi-line inputs are encrypted as one line of OAK.
	@echo
	diff -w <(echo '1')     <(cat Makefile | bin/enigma --encrypt | wc -l)
	@echo
	@echo Multi-line inputs are recoverable.
	@echo
	diff    Makefile        <(cat Makefile | bin/enigma --encrypt | bin/enigma --decrypt)
	@echo
	@echo Only the first line of a multi-line input is decrypted.
	@echo
	@echo The idea is that --decrypt reverses --encrypt, and
	@echo --encrypt only produces a single OAK string.
	@echo
	diff -w <(echo '2')     <(echo -e 'Hello\nGoodbye' | wc -l)
	diff -w <(echo '2')     <(echo -e 'Hello\nGoodbye' | bin/oak --mode encode-lines | wc -l)
	diff    <(echo 'Hello') <(echo -e 'Hello\nGoodbye' | bin/oak --mode encode-lines | bin/enigma --decrypt)
	diff    <(echo 'Hello') <(echo -e 'oak_3CNB_2988590367_15_RjFTVTVfSGVsbG8_ok\noak_3CNB_3136943697_18_RjFTVTdfR29vZGJ5ZQ_ok' | bin/enigma --decrypt)
	@echo
	@echo Encoded secrets are nondeterministic.
	@echo
	! diff <(echo Hello | bin/enigma --encrypt) <(echo Hello | bin/enigma --encrypt) > /dev/null
	@echo
	@echo We can recode one from one key to another
	@echo
	echo Hello | bin/enigma --encrypt | grep '^oak_4foo' > /dev/null
	echo Hello | bin/enigma --encrypt | env ENIGMA_KEYS=bar,foo bin/enigma --recrypt | grep '^oak_4bar' > /dev/null
	diff Makefile <(cat Makefile | bin/enigma --encrypt | env ENIGMA_KEYS=bar,foo bin/enigma --recrypt | bin/enigma --decrypt)
	@echo
	@echo bin/enigma is picky.
	@echo
	! bin/enigma --bogus-garbage-parameter
	@echo
	@echo bin/enigma is friendly.
	@echo
	bin/enigma --help > /dev/null
	bin/enigma        > /dev/null
	diff <(bin/enigma --help) <(bin/enigma)
	@echo
	@echo bin/enigma passed all tests.
	@echo
	@touch $@

# "make test-rubocop" performs our rubocop checks.
#
.PHONY: test-rubocop
test test-rubocop: $(DESTDIR)/test-rubocop.ok
$(DESTDIR)/test-rubocop.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	bundle exec rubocop --version
	bundle exec rubocop --display-cop-names --display-style-guide
	@touch $@
