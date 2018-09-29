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
export OAK_TEST_KEYS=foo,bar
export OAK_TEST_KEY_foo=oak_3CNB_3725491808_52_RjFTQTMyX0qAlJNbIK4fwYY0kh5vNKF5mMpHK-ZBZkfFarRjVPxS_ok
export OAK_TEST_KEY_bar=oak_3CNB_201101230_52_RjFTQTMyXxbYlRcFH8JgiFNZMbnlFTAfUyvJCnXgCESpBmav_Etp_ok

# "make test-shell-encryption" tests the encryption features in bin/oak.
#
.PHONY: test-shell-encryption
test test-shell-encryption: $(DESTDIR)/test-shell-encryption.ok
$(DESTDIR)/test-shell-encryption.ok: $(SOURCES)
	@mkdir -p $(dir $@)
	set -o pipefail ; bin/oak --key-generate | grep '^oak_3[-_0-9a-zA-Z]*_ok$$'
	set -o pipefail ; cat Makefile | bin/oak --mode encode-lines --key-chain OAK_TEST --key foo | bin/oak --mode decode-lines --key-chain OAK_TEST | diff -w Makefile -
	set -o pipefail ; cat Makefile | bin/oak --mode encode-file --key-chain OAK_TEST --key bar | bin/oak --mode decode-file --key-chain OAK_TEST | diff Makefile -
	set -o pipefail ; bin/oak --key-check | grep 'no --key-chain specified'
	set -o pipefail ; bin/oak --key-check --key-chain BOGUS_KEY_CHAIN_TEST | grep 'BOGUS_KEY_CHAIN_TEST: no keys found'
	set -o pipefail ; bin/oak --key-check --key-chain OAK_TEST | grep 'OAK_TEST: found keys: foo bar'
	@echo
	@echo We can recognize which key encrypted which OAK string:
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo We can recode one from one key to another
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key foo | grep '^oak_4foo' > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key foo | bin/oak --mode recode-file --key-chain OAK_TEST --key bar | grep '^oak_4bar' > /dev/null
	@echo
	@echo Both are decodeable as the original source:
	@echo
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key foo | bin/oak --key-chain OAK_TEST --mode decode-file | diff <(echo Hello) - > /dev/null
	echo Hello | bin/oak --mode encode-file --key-chain OAK_TEST --key foo | bin/oak --mode recode-file --key-chain OAK_TEST --key bar | bin/oak --key-chain OAK_TEST --mode decode-file | diff <(echo Hello) - > /dev/null
	@echo
	@echo bin/oak passed all the encryption tests.
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
