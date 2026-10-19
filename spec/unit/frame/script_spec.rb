# frozen_string_literal: true

describe Ferrum::Frame::Script do
  def script(source)
    described_class.new(source)
  end

  describe "#declaration?" do
    {
      "function() { return 1 }" => true,
      "function () {}" => true,
      "function(){}" => true,
      "async function() { await x }" => true,
      "async  function () {}" => true,
      "function*() { yield 1 }" => true,
      "function* () {}" => true,
      "function named(a) { return a }" => true,
      "async function named() {}" => true,
      "function *gen() {}" => true,
      "() => 1" => true,
      "() => {}" => true,
      "() => ({ a: 1 })" => true,
      "(a, b) => a + b" => true,
      "(a = 1, { b }) => a" => true,
      "(...rest) => rest" => true,
      "a => a" => true,
      "$el => $el.id" => true,
      "_ => 1" => true,
      "a => b => a + b" => true,
      "async a => a" => true,
      "async (a) => { await a }" => true,
      "async() => 1" => true,
      "(a)=>a" => true,
      "\n  function() {\n    return 1;\n  }\n" => true,
      "function() {}  ;" => true,
      "function() {};;" => true,
      "/* comment */ function() {}" => true,
      "// comment\nfunction() {}" => true,
      "function() {} // trailing comment" => true,
      "function() {} /* trailing */" => true,
      "function() { return '}' }" => true,
      "function() { return \"}\" }" => true,
      "function() { return `}` }" => true,
      "function() { return `${'}'}` }" => true,
      "function() { return `${ { a: '}' }.a }` }" => true,
      "function() { return /}/.test('}') }" => true,
      "function() { return /[}]/g }" => true,
      "function() { // }\n return 1 }" => true,
      "function() { /* } */ return 1 }" => true,
      "function() { return { a: { b: 1 } } }" => true,
      "function() { if (a) { b() } else { c() } }" => true,
      "function(a = { b: '}' }) { return a }" => true,

      "" => false,
      "   " => false,
      "// only a comment" => false,
      "1 + 1" => false,
      "document.title" => false,
      "window.scrollY;" => false,
      "a; b" => false,
      "(a)" => false,
      "(a) + 1" => false,
      "(1, 2)" => false,
      "(a, b)\n=== c" => false,
      "function() {}()" => false,
      "function() {}.call(this)" => false,
      "(function() {})()" => false,
      "(() => 1)()" => false,
      "function() {} + 1" => false,
      "function() {}; function() {}" => false,
      "functionName()" => false,
      "functions.map(f => f())" => false,
      "async()" => false,
      "async" => false,
      "class A {}" => false,
      "{ a: 1 }" => false,
      "new Function('a', 'return a')" => false,
      "'function() {}'" => false,
      "`() => 1`" => false,
      "// () => 1" => false,
      "[1, 2].map(x => x * 2)" => false,
      "items.filter((a) => a)" => false,
      "x ? () => 1 : 2" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect}" do
        expect(script(source).declaration?).to be(expected)
      end
    end
  end

  describe "#named_function?" do
    {
      "function named() {}" => true,
      "async function named() {}" => true,
      "function* gen() {}" => true,
      "function *gen() {}" => true,
      "function $() {}" => true,
      "function _private() {}" => true,
      "function café() {}" => true,
      "function() {}" => false,
      "function () {}" => false,
      "function*() {}" => false,
      "() => 1" => false,
      "named => 1" => false,
      "function named() {}()" => false,
      "functionName" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect}" do
        expect(script(source).named_function?).to be(expected)
      end
    end
  end

  describe "#code" do
    {
      "1 + 1" => "1 + 1",
      "  1 + 1  " => "1 + 1",
      "\n\n  1 + 1\n\n" => "1 + 1",
      "1 + 1;" => "1 + 1",
      "1 + 1;;  ;" => "1 + 1",
      "1 + 1 // comment" => "1 + 1",
      "1 + 1 /* comment */" => "1 + 1",
      "// leading\n1 + 1" => "1 + 1",
      "/* leading */ 1 + 1" => "1 + 1",
      "/* a */ /* b */ 1 /* c */ // d" => "1",
      "a; b" => "a; b",
      "a; b;" => "a; b",
      "'a // b'" => "'a // b'",
      "\"http://example.com\"" => "\"http://example.com\"",
      "fetch('http://example.com') // fetch" => "fetch('http://example.com')",
      "`a // ${b} // c`" => "`a // ${b} // c`",
      "/\\/\\//.source" => "/\\/\\//.source",
      "a / b // c" => "a / b",
      "'unterminated" => "'unterminated",
      "a /* unterminated" => "a",
      "" => "",
      "   \n  " => "",
      "// only" => "",
      ";" => ""
    }.each do |source, expected|
      it "is #{expected.inspect} for #{source.inspect}" do
        expect(script(source).code).to eq(expected)
      end
    end

    it "keeps a multiline script whole" do
      source = <<~JS
        // set up
        const a = 1;
        const b = { c: '}' };
        return a + b.c; // done
      JS

      expect(script(source).code).to eq("const a = 1;\nconst b = { c: '}' };\nreturn a + b.c")
    end
  end

  describe "#awaits?" do
    {
      "await x" => true,
      "await fetch(url).then(r => r.json())" => true,
      "(await x).y" => true,
      "[await a, await b]" => true,
      "`${await x}`" => true,
      "x\n  .then(await y)" => true,
      "x" => false,
      "obj.await" => false,
      "obj . await" => false,
      "'await'" => false,
      "\"await x\"" => false,
      "`await`" => false,
      "// await x" => false,
      "/* await */ x" => false,
      "awaited" => false,
      "awaitable()" => false,
      "/await/.test(s)" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect}" do
        expect(script(source).awaits?).to be(expected)
      end
    end
  end

  describe "#uses?" do
    {
      "arguments[0]" => true,
      "Array.from(arguments)" => true,
      "`${arguments.length}`" => true,
      "fn.arguments" => false,
      "'arguments'" => false,
      "// arguments" => false,
      "argumentsList" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect} and arguments" do
        expect(script(source).uses?("arguments")).to be(expected)
      end
    end
  end

  describe "#several_statements?" do
    {
      "a(); b" => true,
      "1; 2" => true,
      "{ a: 1 }; 2" => true,
      "a();\nb()" => true,
      "x = 1;" => false,
      "a();;" => false,
      "a(); // comment" => false,
      "(function() { a(); b() })()" => false,
      "for (;;) {}" => false,
      "`${a; b}`" => false,
      "\"a; b\"" => false,
      "// a; b\n1" => false,
      "a\nb" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect}" do
        expect(script(source).several_statements?).to be(expected)
      end
    end
  end

  describe "#leading_line_break?" do
    {
      "\n1 + 1" => true,
      "\n  window.x = 1\n" => true,
      "  \n  1" => true,
      "// comment\n1" => true,
      "/* a\n b */ 1" => true,
      "1 + 1" => false,
      "  1 + 1" => false,
      "/* comment */ 1" => false,
      "1 +\n1" => false,
      "1\n" => false,
      "\n" => false,
      "" => false
    }.each do |source, expected|
      it "is #{expected} for #{source.inspect}" do
        expect(script(source).leading_line_break?).to be(expected)
      end
    end
  end

  describe "#parameters" do
    {
      "function() {}" => [],
      "function(a) {}" => %w[a],
      "function(a, b) {}" => %w[a b],
      "function (a,b,c) {}" => %w[a b c],
      "function(a, b,) {}" => %w[a b],
      "function(\n  a,\n  b\n) {}" => %w[a b],
      "function named(x, y) {}" => %w[x y],
      "async function(a) {}" => %w[a],
      "function*(a) {}" => %w[a],
      "function($el, _value, a1) {}" => %w[$el _value a1],
      "function(café, 名前, ñ1) {}" => %w[café 名前 ñ1],
      "é => é" => %w[é],
      "function(/* first */ a, b /* second */) {}" => %w[a b],
      "function(a, // first\n  b // second\n) {}" => %w[a b],
      "function(a = '/*', b) {}" => %w[a b],
      "function(a = 1, b) {}" => %w[a b],
      "function(a = [1, 2], b = { c: 3 }) {}" => %w[a b],
      "function(a = (1, 2), b) {}" => %w[a b],
      "function(a = ')', b = ',') {}" => %w[a b],
      "function(a = () => 1, b) {}" => %w[a b],
      "function(a = x => x, b) {}" => %w[a b],
      "() => 1" => [],
      "a => a" => %w[a],
      "async a => a" => %w[a],
      "(a, b) => a" => %w[a b],
      "async (a, b) => a" => %w[a b],
      "(a = 1) => a" => %w[a],
      "function({ a }) {}" => nil,
      "function([a, b]) {}" => nil,
      "function(...rest) {}" => nil,
      "function(a, ...rest) {}" => nil,
      "(a, { b }) => a" => nil,
      "({ a, b }) => a" => nil,
      "1 + 1" => nil,
      "" => nil
    }.each do |source, expected|
      it "is #{expected.inspect} for #{source.inspect}" do
        expect(script(source).parameters).to eq(expected)
      end
    end
  end

  describe "broken input" do
    [
      "function() {",
      "function() { return 1",
      "function(a, b",
      "function(a, b) }",
      "() =>",
      "(a, b) =>",
      "=> 1",
      "}}}",
      ")))",
      "]]]",
      "{[(",
      "'unterminated",
      "\"unterminated",
      "`unterminated",
      "`unterminated ${",
      "`${`${`${",
      "/unterminated",
      "/[unterminated",
      "a /* unterminated",
      "\\",
      "@#%^&",
      "\u0000",
      "😀 => 😀",
      "function café(é) { return é }",
      "a" * 10_000,
      "(" * 1_000,
      "function() { #{'{' * 500}#{'}' * 500} }",
      "#{'`${' * 200}#{'}`' * 200}"
    ].each do |source|
      it "reads #{source[0, 30].inspect} without raising" do
        result = script(source)

        expect { [result.code, result.declaration?, result.named_function?, result.awaits?, result.parameters] }
          .not_to raise_error
      end
    end

    {
      "function() {" => false,
      "function() { return 1" => false,
      "function(a, b) }" => false,
      "}}}" => false,
      "'unterminated" => false
    }.each do |source, expected|
      it "doesn't treat #{source.inspect} as a declaration" do
        expect(script(source).declaration?).to be(expected)
      end
    end
  end

  describe "non-ASCII scripts" do
    {
      "\"é\" + 1" => "\"é\" + 1",
      "// café\n1 + 1" => "1 + 1",
      "/* ü */ document.title // ä" => "document.title",
      "'日本語' // コメント" => "'日本語'",
      "`😀 ${a}` // 😀" => "`😀 ${a}`"
    }.each do |source, expected|
      it "reads the code of #{source.inspect}" do
        expect(script(source).code).to eq(expected)
      end
    end

    it "reads a declaration after non-ASCII text" do
      result = script("/* ü */ function(é, b) { return 'ä' } // ö")

      expect(result.declaration?).to be(true)
      expect(result.code).to eq("function(é, b) { return 'ä' }")
      expect(result.parameters).to eq(%w[é b])
    end

    it "reads a binary string as UTF-8" do
      result = script("// \xC3\xA9\nfunction(a) {}".b)

      expect(result.code).to eq("function(a) {}")
      expect(result.declaration?).to be(true)
    end

    it "reads a UTF-16 string" do
      expect(script("(a) => a".encode("UTF-16LE")).parameters).to eq(%w[a])
    end

    it "leaves a script with invalid bytes as it is" do
      source = "1 + \xFF".dup.force_encoding("UTF-8")
      result = script(source)

      expect(result.code.bytes).to eq(source.bytes)
      expect([result.declaration?, result.awaits?, result.parameters, result.leading_line_break?])
        .to eq([false, false, nil, false])
    end
  end

  describe "division and regular expressions" do
    {
      "a / b / c" => "a / b / c",
      "(a) / 2 // half" => "(a) / 2",
      "a[0] / 2 // half" => "a[0] / 2",
      "x = /ab+c/i // regexp" => "x = /ab+c/i",
      "return /a/ // regexp" => "return /a/",
      "typeof /a/" => "typeof /a/",
      "[/a/, /b/]" => "[/a/, /b/]",
      "a ? /x/ : /y/" => "a ? /x/ : /y/",
      "s.replace(/'/g, '\"') // quote" => "s.replace(/'/g, '\"')",
      "s.match(/[/]/) // slash" => "s.match(/[/]/)",
      "s.split(/\\//) // escaped" => "s.split(/\\//)",
      "1 / 2 / '//' // comment" => "1 / 2 / '//'"
    }.each do |source, expected|
      it "reads #{source.inspect}" do
        expect(script(source).code).to eq(expected)
      end
    end
  end
end
