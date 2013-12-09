# -*- encoding: utf-8 -*-
require File.expand_path('../lib/tarantool/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "tarantool"
  gem.version       = Tarantool::VERSION
  gem.summary       = "Tarantool KV-storage client."
  gem.description   = "Tarantool KV-storage client."
  gem.homepage      = "http://github.com/mailru/tarantool-ruby"
  gem.authors       = ["Andrew Rudenko", "Sokolov Yura 'funny-falcon'"]
  gem.email         = ["ceo@prepor.ru", "funny.falcon@gmail.com"]
  gem.license       = "MIT"

  gem.rdoc_options = ["--charset=UTF-8"]
  gem.extra_rdoc_files = %w[README.md LICENSE]

  files             = Dir['lib/**/*'] - ['lib/tarantool/record.rb']
  files            += Dir['test/*'].find_all{|f| !File.directory?(f)} - ['test/test_record.rb']
  files            += %w{Gemfile LICENSE Rakefile README.md}.find_all{|f| File.file?(f)}
  gem.files         = files

  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "iproto", [">= 0.3.8"]
  gem.add_dependency "murmurhash3", [">= 0.1.1"]
  gem.add_dependency "sumbur", [">= 0.0.2"]
  gem.add_dependency "bin_utils", ["~> 0.0.3"]
end
