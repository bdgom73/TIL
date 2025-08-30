source "https://rubygems.org"

gem "jekyll", "~> 4.3.0"
gem "minimal-mistakes-jekyll", "~> 4.24.0"

# Jekyll 플러그인 (GitHub Pages와 호환되는 것만)
group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.17"
  gem "jekyll-seo-tag", "~> 2.8"
  gem "jekyll-sitemap", "~> 1.4"
  gem "jekyll-include-cache", "~> 0.2"
end

# Windows에서 Jekyll 실행을 위한 gem
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1"
  gem "tzinfo-data"
end

# 성능 향상을 위한 gem
gem "wdm", ">= 0.1.0", :platforms => [:mingw, :x64_mingw, :mswin]
gem "webrick", "~> 1.7" 