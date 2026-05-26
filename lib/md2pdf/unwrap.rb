module Md2pdf
  module Unwrap
    module_function

    def call(text)
      lines = text.lines.map(&:rstrip)
      out = []
      in_code = false

      lines.each do |line|
        if line.match?(/\A\s*```/)
          in_code = !in_code
          out << line
          next
        end

        if in_code
          out << line
          next
        end

        if joinable?(out.last, line)
          out[-1] = "#{out[-1]} #{line.lstrip}"
        else
          out << line
        end
      end

      "#{out.join("\n")}\n"
    end

    def joinable?(prev, line)
      return false if prev.nil?
      return false if line.nil?
      return false if line.strip.empty?
      return false if prev.strip.empty?

      stripped = line.lstrip
      return false if stripped.start_with?('#')
      return false if stripped.match?(/\A[-*+] /)
      return false if stripped.match?(/\A\d+\. /)
      return false if stripped.start_with?('>')
      return false if stripped.start_with?('|')
      return false if stripped.start_with?('```')
      return false if stripped.match?(/\A---+\s*\z/)
      return false if stripped.match?(/\A===+\s*\z/)
      return false if stripped.match?(/\A\[.*\]:/)

      prev_s = prev.lstrip
      return false if prev_s.start_with?('#')
      return false if prev_s.start_with?('|')
      return false if prev_s.match?(/\A---+\s*\z/)
      return false if prev_s.match?(/\A===+\s*\z/)

      return false if prev_s.end_with?(':') &&
        line.match?(/\A\s{2,}/)

      true
    end
  end
end
