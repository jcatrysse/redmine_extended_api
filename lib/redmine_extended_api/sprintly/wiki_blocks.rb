# frozen_string_literal: true

require 'nokogiri'

module RedmineExtendedApi
  module Sprintly
    # SPR-521: the text of a wiki page as blocks — paragraphs, headings, list items, table
    # rows, lines of a code block — for comparing versions and for "who wrote this".
    #
    # The SPA saves a page as HTML on a single line, so Redmine's own diff and annotate, which
    # work on lines, see every edit as "the whole page changed". The SPA cuts pages the same
    # way (tracker-ui core/utils/wiki-diff.ts); keep the two in step.
    module WikiBlocks
      BLOCK_TAGS = %w[p h1 h2 h3 h4 h5 h6 li dt dd tr pre blockquote div table ul ol dl figure figcaption
                      section details summary hr br].freeze
      SKIPPED_TAGS = %w[script style template].freeze
      CELL_TAGS = %w[td th].freeze
      HTML = /<[a-z].*>/im

      module_function

      # The readable text of a page, one entry per block, without empty blocks. Legacy pages
      # in a wiki markup are taken line by line.
      def blocks_of(text)
        text = text.to_s
        return [] if text.strip.empty?

        plain = HTML.match?(text) ? html_text(text) : text
        plain.split(/\r?\n/).map { |line| clean(line) }.reject(&:empty?)
      end

      def html_text(html)
        fragment = defined?(Nokogiri::HTML5) ? Nokogiri::HTML5.fragment(html) : Nokogiri::HTML::DocumentFragment.parse(html)
        out = +''
        fragment.children.each { |node| collect(node, out, false) }
        out
      end

      def collect(node, out, in_cell)
        if node.text? || node.cdata?
          out << node.text
          return
        end
        return unless node.element?

        name = node.name.downcase
        return if SKIPPED_TAGS.include?(name)

        cell = CELL_TAGS.include?(name)
        # Inside a table cell the paragraphs the editor wraps its text in stay on the row's line.
        separator = BLOCK_TAGS.include?(name) ? (in_cell ? ' ' : "\n") : ''
        out << separator
        node.children.each { |child| collect(child, out, in_cell || cell) }
        out << separator
        out << ' | ' if cell
      end

      def clean(line)
        line.gsub(/[[:space:]]+/, ' ').strip.sub(/\A(\|\s*)+/, '').sub(/(\s*\|)+\z/, '').strip
      end

      # The shortest edit from `from` to `to` as [op, text] pairs in reading order, op being
      # 'equal', 'delete' or 'insert'; within a changed stretch deletions come first.
      def diff(from, to)
        matches = Redmine::StringArrayDiff::Diff.lcs(from, to)
        ops = []
        next_to = 0
        from.each_with_index do |block, index|
          match = matches[index]
          if match.nil?
            ops << ['delete', block]
          else
            to[next_to...match].each { |added| ops << ['insert', added] }
            ops << ['equal', block]
            next_to = match + 1
          end
        end
        (to[next_to..] || []).each { |added| ops << ['insert', added] }
        ops
      end

      # Who brought each block of `content` (a WikiContentVersion) into the page: an array of
      # [version, author, text]. Core's WikiAnnotate, on blocks instead of lines. The author is
      # nil when the history was cut short and the block is older than what is left.
      def annotate(content)
        current = content
        current_blocks = blocks_of(current.text)
        lines = current_blocks.map { |text| [nil, nil, text] }
        positions = (0...current_blocks.size).to_a
        while (previous = current.previous)
          previous_blocks = blocks_of(previous.text)
          changes = previous_blocks.diff(current_blocks).diffs.flatten
          changes.each_slice(3) do |sign, position, _|
            next unless sign == '+' && positions[position] && positions[position] != -1
            next unless lines[positions[position]][0].nil?

            lines[positions[position]][0] = current.version
            lines[positions[position]][1] = current.author
          end
          changes.each_slice(3) do |sign, position, _|
            if sign == '-'
              positions.insert(position, -1)
            else
              positions[position] = nil
            end
          end
          positions.compact!
          break unless lines.any? { |line| line[0].nil? }

          current = previous
          current_blocks = previous_blocks
        end
        lines.each do |line|
          line[0] ||= current.version
          line[1] ||= current.author if current.version == 1
        end
        lines
      end
    end
  end
end
