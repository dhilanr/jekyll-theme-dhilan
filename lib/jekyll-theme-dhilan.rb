require "cgi"
require "deep_merge"
require "jekyll"
require "jekyll-redirect-from"
require "kramdown/parser/gfm"
require "kramdown/parser/kramdown/link"
require "pathname"
require "sanitize"
require "time"
require "uri"

require "jekyll-theme-dhilan/constants"

# Inspired by http://www.glitchwrks.com/2017/07/25/jekyll-plugins, https://github.com/Shopify/liquid/wiki/Liquid-for-Programmers#create-your-own-tag-blocks

module DHILAN

  # Convert Markdown to HTML, preserving indentation (so that it can still be stripped elsewhere in pipeline)
  def self.convert(s)
    markdown, indentation = DHILAN::unindent(s)
    html = $site.find_converter_instance(::Jekyll::Converters::Markdown).convert(markdown).strip
    DHILAN::indent(html, indentation)
  end

  # Format Time for time.cs50.io
  # https://stackoverflow.com/a/19329068/5156190
  def self.format(t)
    t.strftime("%Y%m%dT%H%M%S%z").sub(/\+0000/, "Z")
  end

  # Indent multiline string
  def self.indent(s, n)
    s.gsub(/^/, " " * n)
  end

  # Sanitize string, allowing only these tags, which are a (reasonable) subset of
  # https://developer.mozilla.org/en-US/docs/Web/Guide/HTML/Content_categories#Phrasing_content
  def self.sanitize(s)
    Sanitize.fragment(s, :elements => ["b", "code", "em", "i", "img", "kbd", "span", "strong", "sub", "sup"]).strip
  end

  # Parse YYYY-MM-DD HH:MM:SS or YYYY-MM-DD HH:MM
  def self.strptime(s)
    begin
      Time.strptime(s, "%Y-%m-%d %H:%M:%S")
    rescue
      begin
        Time.strptime(s, "%Y-%m-%d %H:%M")
      rescue
        raise "Invalid datetime: #{s}"
      end
    end
  end

  # Unindent multiline string
  # https://github.com/mynyml/unindent/blob/master/lib/unindent.rb
  def self.unindent(s)
    n = s.split("\n").select {|line| !line.strip.empty? }.map {|line| line.index(/[^\s]/) }.compact.min || 0
    s = s.gsub(/^[[:blank:]]{#{n}}/, "")
    return s, n
  end

  module Mixins

    def initialize(tag_name, markup, options)
      @tag_name = tag_name
      @markup = markup
      super
    end

    def render(context)

      # Interpolate any variables, a la render_variable in
      # https://github.com/jekyll/jekyll/blob/master/lib/jekyll/tags/include.rb
      output = @markup.gsub(/\{\{.*?\}\}/) do |s|
        Liquid::Template.parse(s).render(context)
      end

      # Quote unquoted URLs
      output = output.gsub(/(\S+\s*=\s*".*"|\S+\s*=\s*'.*'|".*"|'.*'|\S+)/) do |s|
          if s =~ /^#{URI::regexp}$/
            "\"#{s}\""
          else
            s
          end
      end

      # Parse any arguments
      @args, @kwargs = [], {}
      output.scan(/"[^"]*"|'[^']'|\S+\s*=\s*"[^"]*"|\S+\s*=\s*'[^']*'|\S+\s*=\s*\S+|\S+/).each do |s|
        if s.start_with?("'")
          @args.push(s.gsub(/^'|'$/, ""))
        elsif s.start_with?('"')
          @args.push(s.gsub(/^"|"$/, ""))
        else
          key , value = s.split("=", 2)
          if value.nil?
            @args.push(key)
          else
            @kwargs[key] = value
          end
        end
      end

      # Return any content
      super
    end
  end

  class Tag < Liquid::Tag
    include Mixins
  end

  class Block < Liquid::Block
    include Mixins
  end

  class TestTag < Tag	
    def render(context)	
        super	
        puts @args.inspect	
    end	
    Liquid::Template.register_tag("test", self)	
  end

  class AfterBeforeBlock < Block

    def render(context)
      html = DHILAN::convert(super)

      # Parse timestamp
      iso8601 = DHILAN::strptime(@args[0]).iso8601

      # Render HTML
      "<div data-#{@tag_name}='#{iso8601}'>#{html}</div>"
    end

    Liquid::Template.register_tag("after", self)
    Liquid::Template.register_tag("before", self)

  end

  class AlertBlock < Block

    def render(context)
      html = DHILAN::convert(super)
      alert = (["primary", "secondary", "success", "danger", "warning", "info", "light", "dark"].include? @args[0]) ? @args[0] : ""
      "<div class='alert' data-alert='#{alert}' role='alert'>" \
        "#{html}" \
      "</div>"
    end

    Liquid::Template.register_tag("alert", self)

  end

  class CalendarTag < Tag

    # https://gist.github.com/niquepa/4c59b7d52a15dde2367a
    def initialize(tag_name, markup, options)
      super

    end

    def render(context)
      super

      # Deprecated @ctz
      if @kwargs.key?("ctz")
        Jekyll.logger.warn "CS50 warning: no need for @ctz anymore"
      end

      # Calendar's height
      height = @kwargs["height"] || "480"

      # Default components
      components = {
        height: height,
        hl: "en_US",
        mode: @kwargs["mode"] || "AGENDA",
        showCalendars: "0",
        showDate: "0",
        showNav: "0",
        showPrint: "0",
        showTabs: "0",
        showTitle: "0",
        showTz: "1",
        src: @args[0]
      }

      # Build URL
      src = URI::HTTPS.build(:host => "calendar.google.com", :path => "/calendar/embed", :query => URI.encode_www_form(components))

      # Render HTML
      "<iframe data-calendar='#{src}' #{@kwargs['ctz'] ? 'data-ctz' : ''} style='height: #{height}px;'></iframe>"
    end

    Liquid::Template.register_tag("calendar", self)

  end

  class LocalTag < Tag

    @@regex = "\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}(:\d{2})?"

    def render(context)
      super

      # Parse required argument
      if @args.length < 1
        raise "Too few arguments"
      elsif @args.length > 2
        raise "Too many arguments: #{@markup}"
      end
      t1 = DHILAN::strptime(@args[0])
      local = t1.iso8601
      href = "https://time.cs50.io/" + DHILAN::format(t1)

      # Parse optional argument
      if @args.length == 2
        t2 = DHILAN::strptime(@args[1])
        if t2 < t1
          raise "Invalid interval: #{@markup}"
        end
        local += "/" + t2.iso8601
        href += "/" + DHILAN::format(t2)
      end

      # Return
      "<a data-local='#{local}' href='#{href}'></a>"
    end

    Liquid::Template.register_tag("local", self)

  end

  class NextTag < Tag

    def render(context)
      super
      button = DHILAN::sanitize(DHILAN::convert((@args[0]) ? CGI.escapeHTML(@args[0]) : "Next"))
      "<button class='btn btn-dark btn-sm' data-next type='button'>#{button}</button>"
    end

    Liquid::Template.register_tag("next", self)

  end

  class SpoilerBlock < Block

    # https://stackoverflow.com/q/19169849/5156190
    # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/button (re phrasing, but not interactive, content)
    def render(context)
      html = DHILAN::convert(super)
      summary = DHILAN::sanitize(DHILAN::convert((@args[0]) ? CGI.escapeHTML(@args[0]) : "Spoiler"))
      "<details>" \
        "<summary>#{summary}</summary>" \
        "#{html}" \
      "</details>"
    end
    Liquid::Template.register_tag("spoiler", self)

  end

  # Inspired by https://gist.github.com/niquepa/4c59b7d52a15dde2367a
  class VideoTag < Tag

    def render(context)
      super

      # Parse YouTube URL
      if @args[0] 
         
        # If YouTube player
        if @args[0] =~ /^https?:\/\/(?:www\.)?(?:youtube\.com\/(?:[^\/\n\s]+\/\S+\/|(?:v|e(?:mbed)?)\/|\S*?[?&]v=)|youtu\.be\/)([a-zA-Z0-9_-]{11})/

          # Video's ID
          v = $1

          # Default components
          components = {
            "modestbranding" => "0",
            "rel" => "0",
            "showinfo" => "0"
          }

          # Supported components
          params = CGI::parse(URI::parse(@args[0]).query || "")
          ["autoplay", "controls", "end", "index", "list", "mute", "playlist", "start", "t"].each do |param|

            # If param was provided
            if params.key?(param)

              # Add to components, but map t= to start=
              if param == "t" and !params.key?("start")
                components["start"] = params["t"].first
              else
                components[param] = params[param].first
              end
            end
          end

          # Ensure playlist menu appears
          if !params["list"].empty? or !params["playlist"].empty?
            components["showinfo"] = "1"
          end

          # Build URL
          # https://support.google.com/youtube/answer/171780?hl=en
          src = URI::HTTPS.build(:host => "www.youtube.com", :path => "/embed/#{v}", :query => URI.encode_www_form(components))

        # If CS50 Video Player
        elsif @args[0] =~ /^https?:\/\/video\.cs50\.io\/([^?]+)/
          src = @args[0]
        end
      end

      if src
        "<iframe allow='accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture' allowfullscreen class='border' data-video src='#{src}'></iframe>"
      else
        "<p><img alt='static' class='border' data-video src='https://i.imgur.com/xnZ5A2u.gif'></p>"
      end
    end

    Liquid::Template.register_tag("video", self)

  end

  # Disable relative_url filter, since we prepend site.baseurl to all absolute paths,
  # but we're not monkey-patching Jekyll::Filters::URLFilters::relative_url, since it's used by
  # https://github.com/benbalter/jekyll-relative-links/blob/master/lib/jekyll-relative-links/generator.rb
  module Filters
    def relative_url(input)
      Jekyll.logger.warn "CS50 warning: no need to use relative_url with this theme"
      input
    end
  end
  Liquid::Template.register_filter(DHILAN::Filters)

end

Jekyll::Hooks.register :site, :after_reset do |site|

  # Strip trailing slashes from site.baseurl
  unless site.config["baseurl"].nil?
    site.config["baseurl"] = site.config["baseurl"].sub(/\/+$/, "")
  end

  # Disable jekyll-relative-links because it prepends site.baseurl to relative links
  if site.config.key?("plugins") and site.config["plugins"].kind_of?(Array) and site.config["plugins"].include? "jekyll-relative-links"
    site.config["plugins"] = site.config["plugins"] - ["jekyll-relative-links"]
    Jekyll.logger.warn "CS50 warning: no need to use jekyll-relative-links with this theme"
  end

  # Merge in theme's configuration
  site.config = DHILAN::DEFAULTS.dup.deep_merge!(site.config).deep_merge!(DHILAN::OVERRIDES)
end

Jekyll::Hooks.register :site, :pre_render do |site, payload|

  # Expose site to Kramdown's monkey patches
  $site = site

  # Site's time zone
  # https://stackoverflow.com/a/58867058/5156190
  ENV["TZ"] = site.config["dhilan"]["tz"]

  # Promote site.dhilan.assign.* to global variables
  begin
    site.config["dhilan"]["assign"].each do |key, value|
      payload[key] = value
    end
  rescue
  end
end

Jekyll::Hooks.register [:site], :post_render do |site|

  # Paths of pages
  $paths = site.pages.map { |page| page.url }

  def relative_path(from, to)

    # Resolve to relative path
    if !to.start_with?("/")
      to = from + to
    end
    relative = Pathname.new(to).relative_path_from(Pathname.new(from)).to_s

    # If path doesn't end with a trailing slash (before any query or fragment)
    if match = relative.match(/\A([^\?#]+)([\?#].*)?\z/)

      # Construct absolute path
      absolute = match.captures[0] + "/"
      if !absolute.start_with?("/")
        absolute = from + absolute
      end
      absolute = Pathname.new(absolute).cleanpath.to_s + "/"

      # If it should have a trailing slash
      if $paths.include?(absolute)

        # Append trailing slash (plus any query or fragment)
        relative = match.captures[0] + "/"
        if !match.captures[1].nil?
          relative += match.captures[1]
        end
      end
    end

    # Return path
    relative
  end

  # For each page
  site.pages.each do |page|

    # If HTML
    if page.output_ext == ".html"

      # Parse page, including its layout
      doc = Nokogiri::HTML5.parse(page.output)
  
      # For each node in DOM
      doc.traverse do |node|

        # If meta
        if node.name == "meta"

          # Parse url
          if node["content"] =~ /^(\d+;\s*url=["']?)(.+)(["']?)$/i

            # If relative
            if !/^#{URI::regexp}$/.match?($2)

              # Rewrite path
              node["content"] = $1 + relative_path(page.dir, $2) + $3
            end
          end
        end

        # If one of these elements
        {"a" => "href", "img" => "src", "link" => "href", "script" => "src"}.each do |name, attribute|
          if node.name == name

            # With a non-nil attribute
            if !node[attribute].nil?

              # If not a URI (and thus a local path), resolve to relative path
              if node[attribute] !~ /^#{URI::regexp}$/
                node[attribute] = relative_path(page.dir, node[attribute])
              end

           end
          end
        end
      end
      page.output = doc.to_html

    # If CSS
    elsif page.output_ext == ".css"

      # Resolve absolute paths in url() to relative paths
      # https://developer.mozilla.org/en-US/docs/Web/CSS/url()
      page.output = page.output.gsub(/url\(\s*([^\)]*)\s*\)/) do |s|
        group = "#{$1}"
        if match = group.match(/\A'(\/.*)'\z/) # url('/...')
          "url('" + relative_path(page.dir, match.captures[0]).to_s + "')"
        elsif match = group.match(/\A"(\/.*)"\z/) # url("/...")
          'url("' + relative_path(page.dir, match.captures[0]).to_s + '")'
        elsif match = group.match(/\A(\/(.*[^'"])?)\z/) # url(/...)
          "url(" + relative_path(page.dir, match.captures[0]).to_s + ")"
        else
          s
        end
      end
    end

    # TODO: In offline mode, base64-encode images, embed CSS (in style tags) and JS (in script tags), a la
    # https://github.com/jekyll/jekyll-mentions/blob/master/lib/jekyll-mentions.rb and
    # https://github.com/jekyll/jemoji/blob/master/lib/jemoji.rb

  end
end

module Kramdown
  module Parser
    class GFM < Kramdown::Parser::Kramdown

      def parse_autolink
        super

        # Get autolink
        current_link = @tree.children.select{ |element| [:a].include?(element.type) }.last
        unless current_link.nil? 

            # Hide scheme and trailing slash
            current_link.children[0].value = current_link.children[0].value.gsub(/^https?:\/\/(www.)?|\/$/, "")
        end
      end

      def parse_link
        super

        # Get link
        current_link = @tree.children.select{ |element| [:a].include?(element.type) }.last
        unless current_link.nil? 

          # If inline link ends with .md
          if match = current_link.attr["href"].match(/\A([^\s]*)\.md(\s*.*)\z/)

            # Rewrite as /, just as jekyll-relative-links does
            current_link.attr["href"] = match.captures[0] + "/" + match.captures[1]
          end
        end
      end

      # Remember list markers
      def parse_list
        super

        # Get list
        current_list = @tree.children.select{ |element| [:ul].include?(element.type) }.last
        unless current_list.nil?

          # For each li
          current_list.children.each do |li|

            # Line number of li
            location = li.options[:location]

            # Determine marker, might be nested inside of a blockquote
            # https://kramdown.gettalong.org/syntax.html#blockquotes
            li.attr["data-marker"] = @source.lines[location-1].sub(/^[\s>]*/, "")[0]
          end
        end
        true
      end

    end
  end
end
