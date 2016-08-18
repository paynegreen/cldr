# http://unicode.org/reports/tr35/tr35-numbers.html#Language_Plural_Rules
defmodule Cldr.Number.Format.Compiler do
  @moduledoc """
  ## Number Patterns

  Number patterns affect how numbers are interpreted in a localized context.
  Here are some examples, based on the French locale. The "." shows where the
  decimal point should go. The "," shows where the thousands separator should go.
  A "0" indicates zero-padding: if the number is too short, a zero (in the
  locale's numeric set) will go there. A "#" indicates no padding: if the number
  is too short, nothing goes there. A "¤" shows where the currency sign will go.
  The following illustrates the effects of different patterns for the French
  locale, with the number "1234.567". Notice how the pattern characters ',' and
  '.' are replaced by the characters appropriate for the locale.

  ### Number Pattern Examples
  
  Pattern	   | Currency	 | Text
  ---------- | --------- | ----------
  #,##0.##	 | n/a	     | 1 234,57  
  #,##0.###	 | n/a	     | 1 234,567 
  ###0.##### | n/a	     | 1234,567  
  ###0.0000# | n/a	     | 1234,5670 
  00000.0000 | n/a	     | 01234,5670
  #,##0.00 ¤ | EUR	     | 1 234,57 €
                
  The number of # placeholder characters before the decimal do not matter,
  since no limit is placed on the maximum number of digits. There should,
  however, be at least one zero someplace in the pattern. In currency formats,
  the number of digits after the decimal also do not matter, since the
  information in the supplemental data (see Supplemental Currency Data) is used
  to override the number of decimal places — and the rounding — according to
  the currency that is being formatted. That can be seen in the above chart,
  with the difference between Yen and Euro formatting.

  ## Special Pattern Characters

  Many characters in a pattern are taken literally; they are matched during
  parsing and output unchanged during formatting. Special characters, on the
  other hand, stand for other characters, strings, or classes of characters.
  For example, the '#' character is replaced by a localized digit for the
  chosen numberSystem. Often the replacement character is the same as the
  pattern character; in the U.S. locale, the ',' grouping character is replaced
  by ','. However, the replacement is still happening, and if the symbols are
  modified, the grouping character changes. Some special characters affect the
  behavior of the formatter by their presence; for example, if the percent
  character is seen, then the value is multiplied by 100 before being displayed.

  To insert a special character in a pattern as a literal, that is, without any
  special meaning, the character must be quoted. There are some exceptions to
  this which are noted below.

  ### Number Pattern Character Definitions
  
  Symbol | Meaning
  ------ | -------
  0	     | Digit
  1..9   | '1' through '9' indicate rounding
  @	     | Significant digit
  #	     | Digit, omitting leading/trailing zeros
  .	     | Decimal separator or monetary decimal separator
  -	     | Minus sign
  ,	     | Grouping separator
  +	     | Prefix positive exponents with localized plus sign
  %	     | Multiply by 100 and show as percentage
  ‰      | Multiply by 1000 and show as per mille (aka “basis points”)
  ;	     | Separates positive and negative subpatterns
  ¤      | Any sequence is replaced by the localized currency symbol
  *	     | Pad escape, precedes pad character
  '	     | Used to quote special characters in a prefix or suffix
  
  A pattern contains a positive subpattern and may contain a negative
  subpattern, for example, "#,##0.00;(#,##0.00)". Each subpattern has a prefix,
  a numeric part, and a suffix. If there is no explicit negative subpattern,
  the implicit negative subpattern is the ASCII minus sign (-) prefixed to the
  positive subpattern. That is, "0.00" alone is equivalent to "0.00;-0.00".
  (The data in CLDR is normalized to remove an explicit subpattern where it
  would be identical to the explicit form.) If there is an explicit negative
  subpattern, it serves only to specify the negative prefix and suffix; the
  number of digits, minimal digits, and other characteristics are ignored in
  the negative subpattern. That means that "#,##0.0#;(#)" has precisely the
  same result as "#,##0.0#;(#,##0.0#)". However in the CLDR data, the format is
  normalized so that the other characteristics are preserved, just for
  readability.

  Note: The thousands separator and decimal separator in patterns are always
  ASCII ',' and '.'. They are substituted by the code with the correct local
  values according to other fields in CLDR. The same is true of the - (ASCII
  minus sign) and other special characters listed above.
  
  Extracted from [Unicode number formats in TR35]
  (http://unicode.org/reports/tr35/tr35-numbers.html#Number_Formats)
  """
  
  import Kernel, except: [length: 1]
    
  @decimal_separator    "."
  @grouping_separator   ","
  @exponent_separator   "E"
  @currency_placeholder "¤"
  @plus_placeholder     "+"
  @minus_placeholder    "-"
  @digit_omit_zeroes    "#"
  @digits               "[0-9]"
  @significant_digit    "@"
  
  @max_integer_digits   trunc(:math.pow(2, 32))
  @min_integer_digits   0
  
  @max_fraction_digits  @max_integer_digits
  @min_fraction_digits  @min_integer_digits
  
  @digits_pattern       Regex.compile!(@digits)
  @rounding_pattern     Regex.compile!("[" <> @digit_omit_zeroes <> 
    @significant_digit <> @grouping_separator <> "]")
  
  @doc """
  Returns a map of the number placeholder symbols.
  
  These symbols are used in decimal number format
  and are replaced with locale-specific characters
  during number formatting.
  
  ## Example
  
      iex> Cldr.Number.Format.Compiler.placeholders
      %{decimal: ".", exponent: "E", group: ",", minus: "-", plus: "+"}
  """
  @spec placeholders :: %{}
  def placeholders do
    %{
      decimal:  @decimal_separator,
      group:    @grouping_separator,
      exponent: @exponent_separator,
      plus:     @plus_placeholder,
      minus:    @minus_placeholder
    }
  end
  
  @doc """
  Scan a number format definition
  
  Using a leex lexer, tokenize a rule definition
  """
  def tokenize(definition) when is_binary(definition) do
    String.to_charlist(definition) |> :decimal_formats_lexer.string
  end
  
  @doc """
  Parse a number format definition

  Using a yexx lexer, parse a nunber format definition into list of 
  elements we can then interpret to format a number.
  
  ## Example
  
      iex> Cldr.Number.Format.Compiler.parse "¤ #,##0.00;¤-#,##0.00"
      {:ok,
       [positive: [currency: 1, literal: " ", format: "#,##0.00"],
        negative: [currency: 1, minus: '-', format: :same_as_positive]]}
  """
  def parse(tokens) when is_list(tokens) do
    :decimal_formats_parser.parse tokens
  end

  def parse(definition) when is_binary(definition) do
    {:ok, tokens, _end_line} = tokenize(definition)
    tokens |> :decimal_formats_parser.parse
  end
  
  @doc """
  Parse a number format definition and analyze it.

  After parsing, reduce the format to a set of metrics
  that can then be used to format a number.
  
  ## Example
  
      iex> Cldr.Number.Format.Compiler.decode("#")
      %{currency?: false, format: [positive: [format: "#"], negative: nil],
        grouping: %{first: 0, rest: 0}, length: 1, multiplier: 1,
        rounding: #Decimal<1>,
        significant_digits: %{maximum_significant_digits: 0,
          minimum_significant_digits: 0}}
  """
  def decode(definition) do
    case parse(definition) do
    {:ok, format} ->
      analyze(format)
    {:error, {_line, _parser, [message, [context]]}} ->
      {:error, "Decimal format compiler: #{message}#{context}"}
    end
  end
  
  @docp """
  Extract the metadata from the format.
  
  The metadata is used to generate the formatted output.
  """
  defp analyze(format) do
    format_parts = split_format(format)
    %{
      integer_digits:      %{min: required_integer_digits(format_parts),
                             max: @max_integer_digits},
      fractional_digits:   %{min: required_fraction_digits(format_parts),
                             max: optional_fraction_digits(format_parts) +
                                  required_fraction_digits(format_parts)},
      significant_digits:  significant_digits(format_parts),
      exponent:            exponent(format_parts),
      exponent_sign:       exponent_sign(format_parts),
      grouping:            grouping(format_parts),
      rounding:            rounding(format_parts),
      padding_length:      padding_length(format),
      padding_char:        padding_char(format),
      multiplier:          multiplier(format),
      currency?:           currency_format?(format),
      percent?:            percent_format?(format),
      permille?:           permille_format?(format),
      format:              format,
    }
  end
  
  @docp """
  Extact how many integer digits are to be displayed.
  """
  @digits_match Regex.compile!("(?<digits>" <> @digits <> "+)")
  defp required_integer_digits(%{"compact_integer" => integer_format}) do
    if captures = Regex.named_captures(@digits_match, integer_format) do
      String.length(captures["digits"])
    else
      0
    end
  end
  
  @docp """
  Extract how many fraction digits must be displayed.
  """
  defp required_fraction_digits(%{"compact_fraction" => nil}), do: 0
  defp required_fraction_digits(%{"compact_fraction" => fraction_format}) do
    if captures = Regex.named_captures(@digits_match, fraction_format) do
      String.length(captures["digits"])
    else
      0
    end
  end
  
  @docp """
  Extract how many additional fraction digits may be displayed.
  """
  @hashes_match Regex.compile!("(?<hashes>[" <> @digit_omit_zeroes <> "]+)")
  defp optional_fraction_digits(%{"compact_fraction" => ""}), do: 0
  defp optional_fraction_digits(%{"compact_fraction" => fraction_format}) do
    if captures = Regex.named_captures(@hashes_match, fraction_format) do
      String.length(captures["hashes"])
    else
      0
    end
  end
  
  @docp """
  Extract the exponent from the format
  """
  defp exponent(%{"exponent" => ""}), do: 0
  defp exponent(%{"exponent" => exp}) do
    String.to_integer(exp)
  end
  
  @docp """
  Extract whether a + sign was given the format exponent
  """
  def exponent_sign(%{"exponent_sign" => ""}), do: false
  def exponent_sign(%{"exponent_sign" => _exponent_sign}), do: true
  
  @docp """
  Extract the padding length of the format.

  Patterns support padding the result to a specific width. In a pattern the pad
  escape character, followed by a single pad character, causes padding to be
  parsed and formatted. The pad escape character is '*'. For example,
  "$*x#,##0.00" formats 123 to "$xx123.00" , and 1234 to "$1,234.00" .

  When padding is in effect, the width of the positive subpattern, including
  prefix and suffix, determines the format width. For example, in the pattern
  "* #0 o''clock", the format width is 10.

  Some parameters which usually do not matter have meaning when padding is
  used, because the pattern width is significant with padding. In the pattern
  "* ##,##,#,##0.##", the format width is 14. The initial characters "##,##,"
  do not affect the grouping size or maximum integer digits, but they do affect
  the format width.

  Padding may be inserted at one of four locations: before the prefix, after
  the prefix, before the suffix, or after the suffix. No padding can be
  specified in any other location. If there is no prefix, before the prefix and
  after the prefix are equivalent, likewise for the suffix. When specified in a
  pattern, the code point immediately following the pad escape is the pad
  character. This may be any character, including a special pattern character.
  That is, the pad escape escapes the following character. If there is no
  character after the pad escape, then the pattern is illegal.

 This function determines the length of the pattern against which we pad if
  required.
  """
  defp padding_length(format) do
    if format[:positive][:pad] do
      Enum.reduce format[:positive], 0, fn (element, len) ->
        len + case element do
          {:currency, size}   -> size
          {:percent, _}       -> 1
          {:permille, _}      -> 1
          {:plus, _}          -> 1
          {:minus, _}         -> 1
          {:pad, _}           -> 0
          {:literal, literal} -> String.length(literal)
          {:format, format}   -> String.length(format)
        end
      end
    else
      0
    end
  end
  
  @docp """
  The pad character to be applied if padding is in effect.
  """
  def padding_char(format) do
    format[:positive][:pad] || nil
  end
  
  @docp """
  Return a scale factor depending on the format mask.
  
  We multiply the number by a scale factor if the format
  has a percent or permille symbol.
  """
  defp multiplier(format) do
    cond do
      percent_format?(format)   -> Decimal.new(100)
      permille_format?(format)  -> Decimal.new(1000)
      true                      -> Decimal.new(1)
    end
  end
  
  @docp """
  Return the size of the groupings (first and rest) for the format.
  
  A format may have zero, one or two groupings - any others are ignored.
  """
  defp grouping(%{"integer" => integer_format}) do
    [_drop | groups] = String.split(integer_format, @grouping_separator)
    
    grouping = groups
    |> Enum.reverse
    |> Enum.slice(0..1)
    |> Enum.map(&String.length/1)
    
    case grouping do
      [first, rest] ->
        %{first: first, rest: rest}
      [first] ->
        %{first: first, rest: first}
      _ ->
        %{first: 0, rest: 0}
    end
  end
  
  @docp """
  Extracts the significant digit metrics from the format.

  There are two ways of controlling how many digits are shows: (a) significant
  digits counts, or (b) integer and fraction digit counts. Integer and fraction
  digit counts are described above. When a formatter is using significant
  digits counts, it uses however many integer and fraction digits are required
  to display the specified number of significant digits. It may ignore min/max
  integer/fraction digits, or it may use them to the extent possible.

  Significant Digits Examples
  
  Pattern	| Min sign. digits  | Max sign. digits  | Number	  | Output
  ------- | ----------------- | ----------------- | --------- | ------
  @@@	    | 3	                | 3	                | 12345	    | 12300 
  @@@	    | 3	                | 3	                | 0.12345	  | 0.123 
  @@##	  | 2	                | 4	                | 3.14159	  | 3.142 
  @@##	  | 2	                | 4	                | 1.23004	  | 1.23  

  * In order to enable significant digits formatting, use a pattern containing
    the '@' pattern character.

  * In order to disable significant digits formatting, use a pattern that
    does not contain the '@' pattern character.

  * Significant digit counts may be expressed using patterns that specify a
    minimum and maximum number of significant digits. These are indicated by
    the '@' and '#' characters. The minimum number of significant digits is the
    number of '@' characters. The maximum number of significant digits is the
    number of '@' characters plus the number of '#' characters following on the
    right. For example, the pattern "@@@" indicates exactly 3 significant
    digits. The pattern "@##" indicates from 1 to 3 significant digits.
    Trailing zero digits to the right of the decimal separator are suppressed
    after the minimum number of significant digits have been shown. For
    example, the pattern "@##" formats the number 0.1203 as "0.12".

  * Implementations may forbid the use of significant digits in combination
    with min/max integer/fraction digits. In such a case, if a pattern uses
    significant digits, it may not contain a decimal separator, nor the '0'
    pattern character. Patterns such as "@00" or "@.###" would be disallowed.

  * Any number of '#' characters may be prepended to the left of the
    leftmost '@' character. These have no effect on the minimum and maximum
    significant digits counts, but may be used to position grouping separators.
    For example, "#,#@#" indicates a minimum of one significant digits, a
    maximum of two significant digits, and a grouping size of three.

  * The number of significant digits has no effect on parsing.

  * Significant digits may be used together with exponential notation. Such
    patterns are equivalent to a normal exponential pattern with a minimum and
    maximum integer digit count of one, a minimum fraction digit count of
    Minimum Significant Digits - 1, and a maximum fraction digit count of
    Maximum Significant Digits - 1. For example, the pattern "@@###E0" is
    equivalent to "0.0###E0".

  """
  
  # Build up the regex to extract the '@' and following '#' from the pattern
  @leading_digits "([" <> @digit_omit_zeroes <> @grouping_separator <> "]" <> "*)?"
  @min_significant_digits   "(?<ats>" <> @significant_digit <> "+)"
  @max_significant_digits   "(?<hashes>" <> @digit_omit_zeroes <> "*)?"
  @significant_digits_match Regex.compile!(@leading_digits 
      <> @min_significant_digits <> @max_significant_digits)
  
  defp significant_digits(%{"compact_integer" => integer_format}) do
    if captures = Regex.named_captures(@significant_digits_match, integer_format) do
      minimum = String.length(captures["ats"])
      maximim = minimum + String.length(captures["hashes"])
      %{minimum: minimum, maximum: maximim}
    else
      %{minimum: 0, maximum: 0}
    end
  end
  
  @docp """
  Extract the rounding value from a format.

  Patterns support rounding to a specific increment. For example, 1230 rounded
  to the nearest 50 is 1250. Mathematically, rounding to specific increments is
  performed by dividing by the increment, rounding to an integer, then
  multiplying by the increment. To take a more bizarre example, 1.234 rounded
  to the nearest 0.65 is 1.3, as follows:

  | Original:                       | 1.234     |
  | Divide by increment (0.65):     | 1.89846…  |
  | Round:                          | 2         |
  | Multiply by increment (0.65):   | 1.3       |

  To specify a rounding increment in a pattern, include the increment in the
  pattern itself. "#,#50" specifies a rounding increment of 50. "#,##0.05"
  specifies a rounding increment of 0.05.

  * Rounding only affects the string produced by formatting. It does not
  affect parsing or change any numerical values.

  * An implementation may allow the specification of a rounding mode to
  determine how values are rounded. In the absence of such choices, the default
  is to round "half-even", as described in IEEE arithmetic. That is, it rounds
  towards the "nearest neighbor" unless both neighbors are equidistant, in
  which case, it rounds towards the even neighbor. Behaves as for round
  "half-up" if the digit to the left of the discarded fraction is odd; behaves
  as for round "half-down" if it's even. Note that this is the rounding mode
  that minimizes cumulative error when applied repeatedly over a sequence of
  calculations.

  * Some locales use rounding in their currency formats to reflect the smallest
    currency denomination.

  * In a pattern, digits '1' through '9' specify rounding, but otherwise
    behave identically to digit '0'.
  """
  @default_rounding Decimal.new(0)
  defp rounding(%{"integer" => integer_format, "fraction" => fraction_format}) do
    format = integer_format <> "." <> fraction_format 
    |> String.trim_trailing(@decimal_separator)
    
    rounding_chars = String.replace(format, @rounding_pattern, "")
    if String.length(rounding_chars) > 0 do
      Decimal.new(rounding_chars)
    else
      @default_rounding
    end
  end
  
  @docp """
  Separate the format into the integer, fraction and exponent parts.
  
  In the lexer the regex is ([@#,]*)?([0-9]+)?(\.[0-9#,]+)?([Ee](\+)?[0-9]+)?
  """
  @integer_part  "(?<integer>[0-9,@#]+)"
  @fraction_part "((\.(?<fraction>[0-9,#]+))?"
  @exponent_part "([Ee](?<exponent_sign>[+])?(?<exponent>([\+0-9]+)))?)?"
  @format Regex.compile!(@integer_part <> @fraction_part <> @exponent_part)
  
  def number_match_regex do
    @format
  end
  
  defp split_format(format) do
    parts = Regex.named_captures(@format, format[:positive][:format])
    
    parts
    |> Map.put("compact_integer", 
        String.replace(parts["integer"], @grouping_separator, ""))
    |> Map.put("compact_fraction", 
        String.replace(parts["fraction"], @grouping_separator, ""))
  end
  
  defp percent_format?(format) do
    Keyword.has_key? format[:positive], :percent
  end
  
  defp permille_format?(format) do
    Keyword.has_key? format[:positive], :permille
  end
  
  defp currency_format?(format) do
    Keyword.has_key? format[:positive], :currency
  end
end      
         