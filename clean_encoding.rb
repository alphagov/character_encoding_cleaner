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

  def initialize
    @mappings = Hash.new
    load
  end

  def load
    File.open(filename, 'r:binary').read.chomp.split("\n").map do |line|
      bad_sequence, replacement = parse_line(line)
      @mappings[bad_sequence] = replacement
    end
  rescue Errno::ENOENT => e
    []
  end

  def parse_line(line)
    bad_ascii, replacement = line.split(":")
    bad_sequence = bad_ascii.split('\x').reject(&:empty?).map {|byte| byte.to_i(16).chr}.join("")
    [bad_sequence, replacement == 'TODO' ? nil : (replacement || "")]
  end

  def save(file = nil)
    File.open(file || filename, 'w:binary') do |f|
      @mappings.each do |bad_sequence, replacement|
        bytestring = '\x' + bad_sequence.each_byte.map do |byte|
          byte.to_s(16).upcase
        end.join('\x')
        f.write(bytestring)
        f.write(":")
        f.write(replacement || "TODO")
        f.write("\n")
      end
    end
  end

  def filename
    "mappings.txt"
  end

  def include?(bad)
    @mappings.has_key?(bad.to_s)
  end

  def done?(bad)
    ! @mappings[bad.to_s].nil?
  end

  def add(bad)
    @mappings[bad.to_s] = nil unless @mappings.has_key?(bad.to_s)
  end

  def fix(data)
    new_data = data.dup
    in_order = @mappings.sort_by {|k,v| k}.reverse
    first_nil_idx = in_order.find_index {|bad_sequence, replacement| replacement.nil?} || in_order.size
    in_order[0...first_nil_idx].each do |bad_sequence, replacement|
      new_data.gsub!(bad_sequence, replacement)
    end
    new_data
  end

  def is_replacement_target?(str)
    @mappings.values.include?(str)
  end
end


mappings = Mappings.new
data = mappings.fix(data)
if output_file
  File.open(output_file, 'w:binary') do |f|
    f.write(data)
  end
end

f = FilePartitioner.new(/[\x80-\xff]+/n)
parts = f.partition(data)
parts.each_slice(2) do |good, bad|
  next unless bad
  next if mappings.is_replacement_target?(bad.to_s)
  mappings.add(bad)
  puts bad.in_context unless mappings.done?(bad)
end

mappings.save
