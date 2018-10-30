# frozen_string_literal: true

require 'regexp_parser'

module Capybara
  class Selector
    # @api private
    class RegexpDisassembler
      def initialize(regexp)
        @regexp = regexp
      end

      def alternated_substrings
        @options ||= begin
          process(alternation: true)
        end
      end

      def substrings
        @substrings ||= begin
          process(alternation: false).first
        end
      end

    private

      def process(alternation:)
        strs = extract_strings(Regexp::Parser.parse(@regexp), [''], alternation: alternation)
        strs = collapse(combine(strs).map &:flatten)
        strs.each { |str| str.map!(&:upcase) } if @regexp.casefold?
        strs
      end


      def min_repeat(exp)
        exp.quantifier&.min || 1
      end

      def fixed_repeat?(exp)
        min_repeat(exp) == (exp.quantifier&.max || 1)
      end

      def optional?(exp)
        min_repeat(exp).zero?
      end


      def combine(strs)
        suffixes = [[]]
        strs.reverse_each do |str|
          if str.is_a? Set
            prefixes = str.each_with_object([]) { |s, memo| memo.concat combine(s) }

            result = []
            prefixes.product(suffixes) { |pair| result << pair.flatten(1) }
            suffixes = result
          else
            suffixes.each do |arr|
              arr.unshift str
            end
          end
        end
        suffixes
      end

      def collapse(strs)
        strs.map do |substrings|
          substrings.slice_before { |str| str.empty? }.map(&:join).reject(&:empty?).uniq
        end
      end

      def extract_strings(expression, strings, alternation: false)
        expression.each do |exp|
          if optional?(exp)
            strings.push('')
            next
          end

          if %i[meta].include?(exp.type) && !exp.terminal? && alternation
            alternatives = exp.alternatives.map { |sub_exp| extract_strings(sub_exp, [], alternation: true) }
            if alternatives.all? { |alt| alt.any? { |a| !a.empty? } }
              strings.push(Set.new(alternatives))
            else
              strings.push('')
            end
            next
          end

          if %i[meta set].include?(exp.type)
            strings.push('')
            next
          end

          if exp.terminal?
            case exp.type
            when :literal
              strings.push (exp.text * min_repeat(exp))
            when :escape
              strings.push (exp.char * min_repeat(exp))
            else
              strings.push('')
            end
          else
            min_repeat(exp).times { extract_strings(exp, strings, alternation: alternation) }
          end
          strings.push('') unless fixed_repeat?(exp)
        end
        strings
      end
    end
  end
end
