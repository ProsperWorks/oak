lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'oak/version'

Gem::Specification.new do |spec|

  spec.name          = 'oak'
  spec.version       = OAK::VERSION
  spec.platform      = Gem::Platform::RUBY

  spec.authors       = ['jhwillett']
  spec.email         = ['jhw@prosperworks.com']

  spec.summary       = 'Envelope with performance and encryption tradeoffs.'
  spec.homepage      = 'https://github.com/ProsperWorks/oak'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies.
  #
  # TODO: trim these, especially 'contracts'.
  #
  spec.add_runtime_dependency     'bzip2-ffi',   '~> 1.0.0'
  spec.add_runtime_dependency     'contracts',   '~> 0.16.0'
  spec.add_runtime_dependency     'lz4-ruby',    '~> 0.3.3'
  spec.add_runtime_dependency     'optimist',    '~> 3.0.0'
  spec.add_runtime_dependency     'ruby-lzma',   '~> 0.4.3'
  spec.add_runtime_dependency     'rubydoctest', '~> 1.1.5'
  spec.add_development_dependency 'bundler',     '~> 1.16.1'
  spec.add_development_dependency 'minitest',    '~> 5.11.3'
  spec.add_development_dependency 'rake',        '~> 12.3.1'
  spec.add_development_dependency 'rubocop',     '~> 0.54.0'
end
