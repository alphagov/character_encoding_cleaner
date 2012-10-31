#!/usr/bin/env ruby -w
require 'pp'
require 'set'
require 'colorize'
require 'forwardable'

unless ARGV.size >= 1
  puts "Usage: __FILE__ <input file> [<output file>]"
  exit(1)
end

input_file = ARGV[0]
output_file = ARGV[1]
data = File.open(input_file, 'r:binary').read

class FilePartitioner
  def initialize(regexp)
    @regexp = regexp
  end

  def partition(data)
    pos = 0
    data = data.dup.freeze
    tail = data
    parts = []
    begin
      head, match, tail = tail.partition(@regexp)
      parts << Extent.new(data, pos, pos + head.size - 1)
      if ! match.empty?
        parts << Extent.new(data, pos + head.size, pos + head.size + match.size - 1)
        pos += head.size + match.size
      end
    end while !match.empty?
    parts
  end

  class Extent < Struct.new(:data, :from, :to)
    include Comparable

    def value
      data[from..to]
    end

    def to_s
      value
    end

    def in_context(context_size = 30)
      context_start = [from - context_size, 0].max
      context_end = [to + context_size, data.size].min

      pre_context = data[context_start...from]
      post_context = data[to+1...context_end]
      sanitize(pre_context) + to_s.inspect.white.on_red + sanitize(post_context)
    end

    def sanitize(str)
      str.tr(badchars, "")
    end

    def badchars
      ((0..31).map(&:chr) + (0x80...0xa0).map(&:chr)).join("")
    end

    def <=>(other)
      self.value <=> other.value
    end

    def hash
      self.value.hash
    end

    def eql?(other)
      self.value == other.value
    end
  end
end

class Mappings
  attr_reader :mappings

  class Mapping < Struct.new(:line_number, :bad_sequence, :replacement)
  end

  def initialize
    @mappings = []
    load
  end

  def load
    line_number = 1
    File.open(filename, 'r:binary').read.chomp.split("\n").map do |line|
      bad_sequence, replacement = parse_line(line)
      @mappings << Mapping.new(line_number, bad_sequence, replacement)
      line_number += 1
    end
  rescue Errno::ENOENT
    []
  end

  def parse_line(line)
    bad_ascii, replacement = line.split(":")
    bad_sequence = bad_ascii.split('\x').reject(&:empty?).map {|byte| byte.to_i(16).chr}.join("")
    [bad_sequence, replacement == 'TODO' ? nil : (replacement || "")]
  end

  def save(file = nil)
    File.open(file || filename, 'w:binary') do |f|
      @mappings.each do |mapping|
        bytestring = '\x' + mapping.bad_sequence.each_byte.map do |byte|
          byte.to_s(16).upcase
        end.join('\x')
        f.write(bytestring)
        f.write(":")
        f.write(mapping.replacement || "TODO")
        f.write("\n")
      end
    end
  end

  def filename
    "mappings.txt"
  end

  def find_mapping(bad_sequence)
    @mappings.find { |mapping| mapping.bad_sequence == bad_sequence.to_s }
  end

  def include?(bad_sequence)
    ! find_mapping(bad_sequence).nil?
  end

  def done?(bad_sequence)
    mapping = find_mapping(bad_sequence)
    mapping && mapping.replacement
  end

  def add(bad_sequence)
    @mappings << Mapping.new(@mappings.size + 1, bad_sequence.to_s, nil) unless include?(bad_sequence.to_s)
    find_mapping(bad_sequence).line_number
  end

  def fix(data)
    new_data = data.dup
    in_order = @mappings.sort_by {|mapping| mapping.bad_sequence.size}.reverse
    first_nil_idx = in_order.find_index {|mapping| mapping.replacement.nil?} || in_order.size
    in_order[0...first_nil_idx].each do |mapping|
      new_data = apply_replacement(new_data, mapping.bad_sequence, mapping.replacement, mapping.line_number)
    end
    new_data
  end

  def apply_replacement(data, sequence, replacement, line_number)
    pos = 0
    shown = false
    found = 0

    puts "\n#{line_number}: => #{replacement} "
    while from = data.index(sequence, pos)
      to = from + sequence.size - 1
      new_data = data.dup
      new_data[from..to] = replacement
      new_data.freeze
      new_to = from + replacement.size - 1
      show(data, from, to, :red) unless shown
      show(new_data, from, new_to, :green) unless shown
      data = new_data
      pos = new_to
      found +=1
    end
    puts "   ... (replaced #{found})"
    data
  end

  def show(data, from, to, background_colour, context=30)
    context_start = [0, from-context].max
    context_end = [data.size, to+context].min
    puts(
      data[context_start...from].gsub("\n", "\\n") +
      data[from..to].white.colorize(background: background_colour) +
      data[(to+1)..context_end].gsub("\n", "\\n")
      )
  end

  def is_replacement_target?(str)
    @mappings.any? { |mapping| mapping.replacement == str }
  end
end


mappings = Mappings.new
data = mappings.fix(data)

partitioner = FilePartitioner.new(/[\x80-\xff]+/n)
parts = partitioner.partition(data)
puts "\n\nRemaining unmapped bad sequences:"
number_remaining = 0
parts.each_slice(2) do |good, bad|
  next unless bad
  next if mappings.is_replacement_target?(bad.to_s)
  next if mappings.done?(bad)
  number_remaining += 1
  mapping_number = mappings.add(bad)
  puts "#{mapping_number}: #{bad.in_context}"
end

if number_remaining == 0
  puts "  None."
end

puts "\n"
if output_file
  File.open(output_file, 'w:binary') do |f|
    f.write(data)
  end
  puts "Wrote cleaned file to #{output_file}."
else
  puts "No output file requested."
end

mappings.save
