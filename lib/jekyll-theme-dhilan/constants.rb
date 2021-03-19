module DHILAN

  PLUGINS = {
    "jekyll-algolia" => "1.6.0",
    "jekyll-default-layout" => "0.1.5",
    "jekyll-optional-front-matter" => "0.3.2",
    "jekyll-redirect-from" => "0.16.0",
    "jekyll-titles-from-headings" => "0.5.3"
  }.freeze

  DEFAULTS = {
    "dhilan" => {
      "locale" => "en",
      "tz" => "America/New_York"
    },
    "exclude" => [
      "Gemfile",
      "Gemfile.lock",
      "vendor"
    ],
    "include" => [
      "license.md" # For OCW
    ],
    "optional_front_matter" => {
      "remove_originals" => true
    },
    "plugins"  => DHILAN::PLUGINS.keys
  }.freeze

  OVERRIDES = {
    "kramdown" => {
      "gfm_quirks" => "paragraph_end",
      "hard_wrap" => false,
      "input" => "GFM",
      "math_engine" => "mathjax",
      "syntax_highlighter" => "rouge",
      "template" => ""
    },
    "markdown" => "kramdown",
    "permalink" => "pretty",
    "redirect_from" => {
      "json" => false
    },
    "sass" => {
      "style" => "compressed"
    },
    "theme" => "jekyll-theme-dhilan"
  }.freeze

end
