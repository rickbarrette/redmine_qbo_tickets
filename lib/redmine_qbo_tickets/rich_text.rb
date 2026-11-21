#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboTickets
  # Formatted text (e.g. an appointment's notes) as blocks the ticket can draw: run through Redmine's own text
  # formatter (Markdown or Textile, Administration » Settings » Text formatting), then turned from HTML into
  #
  #   [{ type:, level:, marker:, quote:, runs: [{ t:, b:, i:, s:, c:, br:, box: }] }]
  #
  #   type    p (paragraph), h (heading, level 1-6), li (list item, level = nesting from 1, marker '•' or '1.'),
  #           alert (a Markdown alert's title, e.g. IMPORTANT), code (code block), hr (rule)
  #   quote   how deep in quotes and alerts it is (drawn with a bar on the left)
  #   runs    the text: b bold, i italic, s struck through, c code; br a line break; box a checkbox (true when
  #           ticked, false when not)
  class RichText
    BLOCK_TAGS = %w[p div h1 h2 h3 h4 h5 h6 ul ol li blockquote pre hr table thead tbody tr].freeze
    ALERT = /\Amarkdown-alert-(?<type>[a-z]+)\z/

    def self.blocks(text)
      return [] if text.blank?

      new.blocks(html(text))
    end

    def self.html(text)
      Redmine::WikiFormatting.formatter_for(Setting.text_formatting).new(text).to_html
    rescue StandardError => e
      Rails.logger.warn "[redmine_qbo_tickets] Formatting failed (#{e.message}), printing the text as it is"
      ERB::Util.html_escape(text).gsub("\n", '<br>')
    end

    def blocks(html)
      @blocks = []
      walk(Nokogiri::HTML5.fragment(html.to_s), quote: 0, depth: 0)
      @blocks.each { |block| tidy(block[:runs]) unless block[:type] == 'code' }
      @blocks.reject { |block| block[:runs].empty? && %w[p li h code].include?(block[:type]) }
    end

    private

    # Block-level nodes; stray inline content becomes a paragraph
    def walk(node, quote:, depth:)
      inline = []
      flush = lambda do
        add('p', runs_of(inline), quote: quote) if inline.any?
        inline = []
      end

      node.children.each do |child|
        name = child.element? ? child.name : nil
        if name.nil? || !BLOCK_TAGS.include?(name)
          inline << child
          next
        end

        flush.call
        case name
        when 'p' then add('p', runs_of(child.children), quote: quote) unless child['class'] == 'markdown-alert-title'
        when /\Ah([1-6])\z/ then add('h', runs_of(child.children), quote: quote, level: Regexp.last_match(1).to_i)
        when 'ul', 'ol' then list(child, quote: quote, depth: depth + 1)
        when 'blockquote' then walk(child, quote: quote + 1, depth: depth)
        when 'pre' then add('code', code_lines(child.text), quote: quote)
        when 'hr' then add('hr', [], quote: quote)
        when 'table', 'thead', 'tbody' then walk(child, quote: quote, depth: depth)
        when 'tr' then add('p', table_row(child), quote: quote)
        when 'div' then div(child, quote: quote, depth: depth)
        else walk(child, quote: quote, depth: depth)
        end
      end
      flush.call
    end

    # A Markdown alert (> [!IMPORTANT]): its title, then its text in a quote; any other div: its content
    def div(node, quote:, depth:)
      type = node['class'].to_s.split.filter_map { |name| name[ALERT, :type] }.first
      if type
        title = node.at_css('.markdown-alert-title')&.text.to_s.squish.presence || type.capitalize
        add('alert', [{ t: title.upcase }], quote: quote)
        walk(node, quote: quote + 1, depth: depth)
      else
        walk(node, quote: quote, depth: depth)
      end
    end

    def list(node, quote:, depth:)
      number = (node['start'] || 1).to_i
      node.element_children.each do |item|
        next walk(item, quote: quote, depth: depth) unless item.name == 'li'

        marker = node.name == 'ol' ? "#{number}." : '•'
        number += 1
        marker = '' if item.at_css('> input[type=checkbox]')
        content, nested = item.children.partition { |child| !(child.element? && %w[ul ol].include?(child.name)) }
        # A loose list wraps its items in <p>: read their text as the item's
        inline = content.flat_map { |child| child.element? && child.name == 'p' ? child.children.to_a + [:br] : [child] }
        add('li', runs_of(inline), quote: quote, level: depth, marker: marker)
        nested.each { |child| list(child, quote: quote, depth: depth + 1) }
      end
    end

    # A code block's lines, as they are
    def code_lines(text)
      text.chomp.split("\n", -1).flat_map { |line| [{ br: true }, { t: line, c: true }] }.drop(1)
    end

    def table_row(node)
      runs = []
      node.element_children.each_with_index do |cell, index|
        runs << { t: ' | ' } if index.positive?
        runs.concat(runs_of(cell.children, cell.name == 'th' ? { b: true } : {}))
      end
      runs
    end

    def add(type, runs, quote:, level: nil, marker: nil)
      @blocks << { type: type, level: level, marker: marker, quote: quote, runs: runs }.compact
    end

    # Inline nodes as styled runs
    def runs_of(nodes, style = {})
      nodes.flat_map do |node|
        next [{ br: true }] if node == :br
        next [] if node.comment?
        next [style.merge(t: node.text)] if node.text?

        case node.name
        when 'strong', 'b' then runs_of(node.children, style.merge(b: true))
        when 'em', 'i' then runs_of(node.children, style.merge(i: true))
        when 'del', 's', 'strike' then runs_of(node.children, style.merge(s: true))
        when 'code', 'kbd', 'samp' then runs_of(node.children, style.merge(c: true))
        when 'br' then [{ br: true }]
        when 'input' then node['type'] == 'checkbox' ? [{ box: node.has_attribute?('checked') }] : []
        when 'img' then node['alt'].present? ? [style.merge(t: node['alt'])] : []
        when 'svg', 'script', 'style' then []
        else runs_of(node.children, style)
        end
      end
    end

    # Spaces tidied as a browser would: white space becomes one space, none at the start or end of a line
    def tidy(runs)
      runs.each { |run| run[:t] = run[:t].gsub(/\s+/, ' ') if run[:t] }
      line_start = true
      runs.each do |run|
        if run[:br]
          line_start = true
        elsif run[:t]
          run[:t] = run[:t].lstrip if line_start
          line_start = false unless run[:t].empty?
        else
          line_start = false # a checkbox
        end
      end
      line_end = true
      runs.reverse_each do |run|
        if run[:br]
          line_end = true
        elsif run[:t]
          run[:t] = run[:t].rstrip if line_end
          line_end = false unless run[:t].empty?
        else
          line_end = false
        end
      end
      runs.reject! { |run| run[:t] == '' }
      runs.shift while runs.first&.dig(:br)
      runs.pop while runs.last&.dig(:br)
      runs
    end
  end
end
