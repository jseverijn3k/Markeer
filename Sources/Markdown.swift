import Foundation

struct RenderBlock: Codable {
    let id: Int
    let html: String
    let source: String
}
struct RenderedMarkdown: Codable {
    let blocks: [RenderBlock]
    let references: String
}

enum Markdown {
    static func render(_ source: String) -> RenderedMarkdown {
        cmark_gfm_core_extensions_ensure_registered()
        let options = Int32(CMARK_OPT_DEFAULT)
        guard let parser = cmark_parser_new(options) else { return .init(blocks: [], references: "") }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist", "tagfilter"] {
            name.withCString { if let ext = cmark_find_syntax_extension($0) { cmark_parser_attach_syntax_extension(parser, ext) } }
        }
        source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
        guard let root = cmark_parser_finish(parser) else { return .init(blocks: [], references: "") }
        defer { cmark_node_free(root) }
        preserveInlineHTML(root)
        let lines = source.components(separatedBy: "\n")
        var covered = Set<Int>()
        var blocks: [RenderBlock] = []
        var node = cmark_node_first_child(root)
        while let current = node {
            let start = max(0, Int(cmark_node_get_start_line(current)) - 1)
            let end = min(lines.count - 1, Int(cmark_node_get_end_line(current)) - 1)
            let original = start <= end ? lines[start...end].joined(separator: "\n") : ""
            if start <= end { covered.formUnion(start...end) }
            var html = ""
            if cmark_node_get_type(current) == CMARK_NODE_HTML_BLOCK {
                html = "<pre class=\"raw-html\" contenteditable=\"false\">" + escape(original) + "</pre>"
            } else if let rendered = cmark_render_html(current, options, cmark_parser_get_syntax_extensions(parser)) {
                html = String(cString: rendered)
                free(rendered)
            }
            blocks.append(.init(id: blocks.count, html: html, source: original))
            node = cmark_node_next(current)
        }
        let references = lines.enumerated().filter { !covered.contains($0.offset) && !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.element).joined(separator: "\n")
        return .init(blocks: blocks, references: references)
    }
    static func preserveInlineHTML(_ node: OpaquePointer) {
        var child = cmark_node_first_child(node)
        while let current = child {
            child = cmark_node_next(current)
            if cmark_node_get_type(current) == CMARK_NODE_HTML_INLINE,
               let literal = cmark_node_get_literal(current),
               let replacement = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) {
                let safe = "<code data-raw-inline=\"true\">" + escape(String(cString: literal)) + "</code>"
                safe.withCString { _ = cmark_node_set_on_enter(replacement, $0) }
                _ = cmark_node_set_on_exit(replacement, "")
                if cmark_node_replace(current, replacement) != 0 { cmark_node_free(current) }
                else { cmark_node_free(replacement) }
            } else { preserveInlineHTML(current) }
        }
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct NumberedListEdit {
    let range: NSRange
    let text: String
}

enum MarkdownEditing {
    static func numberedList(in text: String, selection: NSRange) -> NumberedListEdit {
        let source = text as NSString
        let location = min(selection.location, source.length)
        var length = min(selection.length, source.length - location)
        // A selection ending at the next line's start must leave that line alone.
        if length > 0 && source.character(at: location + length - 1) == 10 { length -= 1 }
        let range = source.lineRange(for: NSRange(location: location, length: length))
        let block = source.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }
        let prefix = try! NSRegularExpression(pattern: "^([ \t]*)(?:[-+*][ \t]+|[0-9]+[.)][ \t]+)")
        var number = 1
        let numbered = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1 { return line }
            let clean = prefix.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "$1")
            let indent = String(clean.prefix(while: { $0 == " " || $0 == "\t" }))
            defer { number += 1 }
            return indent + "\(number). " + clean.dropFirst(indent.count)
        }.joined(separator: "\n")
        return .init(range: range, text: numbered + (trailingNewline ? "\n" : ""))
    }
}
