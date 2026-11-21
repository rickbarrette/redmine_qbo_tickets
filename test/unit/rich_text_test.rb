#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class RichTextTest < ActiveSupport::TestCase
  def blocks(text)
    Setting.stubs(:text_formatting).returns('common_mark')
    RedmineQboTickets::RichText.blocks(text)
  end

  def test_paragraphs_and_line_breaks
    assert_equal [{ type: 'p', quote: 0, runs: [{ t: 'line one' }, { br: true }, { t: 'line two' }] },
                  { type: 'p', quote: 0, runs: [{ t: 'second' }] }],
                 blocks("line one\nline two\n\nsecond")
  end

  def test_inline_styles
    runs = blocks('a **bold** _it_ ~~gone~~ `x` [link](http://example.com)')[0][:runs]
    assert_equal [{ t: 'a ' }, { b: true, t: 'bold' }, { t: ' ' }, { i: true, t: 'it' }, { t: ' ' },
                  { s: true, t: 'gone' }, { t: ' ' }, { c: true, t: 'x' }, { t: ' ' }, { t: 'link' }], runs
  end

  def test_lists_nest_and_number
    result = blocks("- one\n  - two\n\n3. three\n4. four")
    assert_equal [['li', 1, '•', 'one'], ['li', 2, '•', 'two'], ['li', 1, '3.', 'three'], ['li', 1, '4.', 'four']],
                 result.map { |b| [b[:type], b[:level], b[:marker], b[:runs].map { |r| r[:t] }.join] }
  end

  def test_task_lists_get_boxes
    result = blocks("- [ ] tires\n- [x] oil")
    assert_equal [{ box: false }, { t: ' tires' }], result[0][:runs]
    assert_equal [{ box: true }, { t: ' oil' }], result[1][:runs]
    assert_equal '', result[0][:marker]
  end

  def test_headings_quotes_rules_and_code
    result = blocks("## Parts\n\n> waiting\n\n---\n\n```\nP0420  cat\n```")
    assert_equal({ type: 'h', level: 2, quote: 0, runs: [{ t: 'Parts' }] }, result[0])
    assert_equal({ type: 'p', quote: 1, runs: [{ t: 'waiting' }] }, result[1])
    assert_equal 'hr', result[2][:type]
    assert_equal({ type: 'code', quote: 0, runs: [{ t: 'P0420  cat', c: true }] }, result[3])
  end

  def test_tables_print_as_rows
    result = blocks("| a | b |\n|---|---|\n| 1 | 2 |")
    assert_equal [{ b: true, t: 'a' }, { t: ' | ' }, { b: true, t: 'b' }], result[0][:runs]
    assert_equal [{ t: '1' }, { t: ' | ' }, { t: '2' }], result[1][:runs]
  end

  def test_plain_text_formatting
    Setting.stubs(:text_formatting).returns('')
    assert_equal [{ t: '**not** bold' }], RedmineQboTickets::RichText.blocks('**not** bold')[0][:runs]
  end

  def test_nothing
    assert_equal [], blocks('')
  end
end
