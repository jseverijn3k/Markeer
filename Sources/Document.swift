import AppKit
import UniformTypeIdentifiers

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var content = ""
    override class var autosavesInPlace: Bool { true }
    override var autosavingFileType: String? { "net.markeer.markdown" }
    override func makeWindowControllers() {
        let controller=EditorWindowController(document:self)
        addWindowController(controller)
    }
    override func data(ofType typeName:String) throws -> Data {
        guard let data=content.data(using:.utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return data
    }
    override func read(from data:Data, ofType typeName:String) throws {
        let hasUTF16BOM = data.starts(with:[0xff,0xfe]) || data.starts(with:[0xfe,0xff])
        let importedUTF16 = hasUTF16BOM && data.count % 2 == 0 ? String(data:data,encoding:.utf16) : nil
        guard let text=String(data:data,encoding:.utf8) ?? importedUTF16 else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        content=text
        for window in windowControllers { (window as? EditorWindowController)?.reloadFromDocument() }
    }
    override func fileNameExtension(forType typeName:String, saveOperation:NSDocument.SaveOperationType) -> String? { "md" }
    override var fileURL:URL? {
        didSet { for controller in windowControllers { (controller as? EditorWindowController)?.refreshFileLocation() } }
    }
}
