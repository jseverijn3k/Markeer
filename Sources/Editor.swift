import AppKit
import WebKit

final class WeakScriptHandler:NSObject,WKScriptMessageHandler {
    weak var owner:EditorWindowController?
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {owner?.userContentController(controller,didReceive:message)}
}

final class EditorWindowController: NSWindowController, NSTextViewDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSToolbarDelegate {
    weak var markdownDocument:MarkdownDocument?
    let messageProxy=WeakScriptHandler()
    let textView=NSTextView()
    let scroll=NSScrollView()
    let split=NSSplitView()
    let status=NSTextField(labelWithString:"")
    let modeControl=NSSegmentedControl(labels:["Markdown","Opgemaakt","Naast elkaar"],trackingMode:.selectOne,target:nil,action:nil)
    var web:WKWebView!
    var mode=2
    var updating=false
    var ready=false
    var revision=0
    var webDirty=true
    var renderWork:DispatchWorkItem?

    init(document:MarkdownDocument) {
        markdownDocument=document
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.minSize=NSSize(width:640,height:420)
        window.title="Markeer"
        window.setFrameAutosaveName("MarkeerEditor")
        window.center()
        window.tabbingMode = .preferred
        super.init(window:window)
        setup()
    }
    required init?(coder:NSCoder) { fatalError() }
    func setup() {
        guard let window else {return}
        let root=NSView(); window.contentView=root
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        messageProxy.owner=self
        for name in ["changed","ready","openLink","error"] { configuration.userContentController.add(messageProxy,name:name) }
        web=WKWebView(frame:.zero,configuration:configuration)
        web.navigationDelegate=self
        web.setValue(false,forKey:"drawsBackground")
        scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        scroll.borderType = .noBorder
        textView.isRichText=false
        textView.isAutomaticQuoteSubstitutionEnabled=false
        textView.isAutomaticDashSubstitutionEnabled=false
        textView.isAutomaticTextReplacementEnabled=false
        textView.isAutomaticSpellingCorrectionEnabled=false
        textView.isContinuousSpellCheckingEnabled=false
        textView.isGrammarCheckingEnabled=false
        textView.isAutomaticLinkDetectionEnabled=false
        textView.allowsUndo=true
        textView.usesFindBar=true
        textView.font = .monospacedSystemFont(ofSize:15,weight:.regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset=NSSize(width:30,height:34)
        textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false
        textView.autoresizingMask=[.width]
        textView.textContainer?.widthTracksTextView=true
        textView.textContainer?.containerSize=NSSize(width:500,height:CGFloat.greatestFiniteMagnitude)
        textView.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        textView.delegate=self
        textView.setAccessibilityLabel("Markdown-editor")
        scroll.documentView=textView
        split.isVertical=true;split.dividerStyle = .thin
        split.addArrangedSubview(scroll);split.addArrangedSubview(web)
        split.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(split)
        status.font = .systemFont(ofSize:11,weight:.medium)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo:root.topAnchor), split.leadingAnchor.constraint(equalTo:root.leadingAnchor),split.trailingAnchor.constraint(equalTo:root.trailingAnchor),split.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-9),
            status.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),status.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-9),status.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16)
        ])
        let toolbar=NSToolbar(identifier:"MarkeerToolbar")
        toolbar.delegate=self;toolbar.displayMode = .iconOnly;toolbar.allowsUserCustomization=false
        window.toolbar=toolbar; window.toolbarStyle = .unified
        modeControl.target=self;modeControl.action=#selector(changeMode(_:));modeControl.selectedSegment=mode
        modeControl.setAccessibilityLabel("Weergave")
        modeControl.toolTip="Schakel tussen Markdown, opgemaakt en naast elkaar (⌘⇧P)"
        reloadFromDocument()
        if let url=Bundle.main.url(forResource:"editor",withExtension:"html") {
            web.loadFileURL(url,allowingReadAccessTo:URL(fileURLWithPath:"/",isDirectory:true))
        }
        DispatchQueue.main.async { self.split.setPosition(540,ofDividerAt:0);window.makeFirstResponder(self.textView) }
    }
    deinit { web?.configuration.userContentController.removeAllScriptMessageHandlers() }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("new"),NSToolbarItem.Identifier("open"),NSToolbarItem.Identifier("save"),.flexibleSpace,NSToolbarItem.Identifier("modes"),.flexibleSpace,NSToolbarItem.Identifier("bold"),NSToolbarItem.Identifier("italic"),NSToolbarItem.Identifier("heading"),NSToolbarItem.Identifier("list"),NSToolbarItem.Identifier("numberedList"),NSToolbarItem.Identifier("link")]
    }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier identifier:NSToolbarItem.Identifier,willBeInsertedIntoToolbar flag:Bool)->NSToolbarItem? {
        let item=NSToolbarItem(itemIdentifier:identifier)
        if identifier.rawValue=="modes" { item.view=modeControl;item.label="Weergave";return item }
        let config:[String:(String,String,Selector)] = [
            "new":("Nieuw document","doc.badge.plus",#selector(newFile)),"open":("Openen","folder",#selector(openFile)),"save":("Bewaren","square.and.arrow.down",#selector(saveFile)),
            "bold":("Vet (⌘B)","bold",#selector(bold)),"italic":("Cursief (⌘I)","italic",#selector(italic)),"heading":("Kop","textformat.size.larger",#selector(heading)),"list":("Opsomming","list.bullet",#selector(list)),"numberedList":("Genummerde lijst (⌘⇧O)","list.number",#selector(numberedList)),"link":("Link invoegen","link",#selector(link))]
        guard let (label,symbol,action)=config[identifier.rawValue] else {return nil}
        item.label=label;item.toolTip=label;item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)
        item.target=self;item.action=action
        if identifier.rawValue == "numberedList" { item.visibilityPriority = .high }
        return item
    }
    @objc func newFile() { NSDocumentController.shared.newDocument(nil) }
    @objc func openFile() { NSDocumentController.shared.openDocument(nil) }
    @objc func saveFile() { markdownDocument?.save(nil) }
    @objc func changeMode(_ sender:NSSegmentedControl) { setMode(sender.selectedSegment) }
    @objc func cycleMode(_ sender:Any?) { setMode((mode+1)%3) }
    @objc func sourceMode(_ sender:Any?) { setMode(0) }
    @objc func richMode(_ sender:Any?) { setMode(1) }
    @objc func splitMode(_ sender:Any?) { setMode(2) }
    func setMode(_ next:Int) {
        mode=next; modeControl.selectedSegment=next
        scroll.isHidden=next==1;web.isHidden=next==0
        split.adjustSubviews()
        if next != 0 && webDirty { renderNow() }
        if next==0 { window?.makeFirstResponder(textView) }
        else if next==1 { window?.makeFirstResponder(web); web.evaluateJavaScript("markeer.editor.focus()",completionHandler:nil) }
        updateStatus()
    }
    func reloadFromDocument() {
        updating=true;textView.string=markdownDocument?.content ?? "";updating=false
        revision += 1;webDirty=true;renderNow();updateStatus()
    }
    func refreshFileLocation() {
        // Bewaren mag het DOM niet vervangen: WebKit's undo blijft zo bij dezelfde tekstnodes.
        if ready,let folder=markdownDocument?.fileURL?.deletingLastPathComponent().absoluteString {
            web.evaluateJavaScript("markeer.setBasePath(\(jsString(folder)))",completionHandler:nil)
        }
        updateStatus()
    }
    func textDidChange(_ notification:Notification) {
        guard !updating,let document=markdownDocument else {return}
        document.content=textView.string;document.updateChangeCount(.changeDone)
        revision += 1;webDirty=true;renderNow();updateStatus()
    }
    func renderNow() {
        guard ready,mode != 0,let document=markdownDocument else {return}
        let rendered=Markdown.render(document.content)
        guard let data=try? JSONEncoder().encode(rendered),let payload=String(data:data,encoding:.utf8) else {return}
        let source=jsString(document.content)
        let folder=jsString(document.fileURL?.deletingLastPathComponent().absoluteString ?? "")
        web.evaluateJavaScript("markeer.setContent(\(payload),\(revision),\(source),\(folder))") { _,error in
            if let error { NSLog("Markeer rendering error: %@",error.localizedDescription) }
        }
        webDirty=false
    }
    func jsString(_ value:String)->String { String(data:try! JSONEncoder().encode(value),encoding:.utf8)! }
    func updateStatus() {
        let content=markdownDocument?.content ?? ""
        let words=content.split(whereSeparator:{$0.isWhitespace}).count
        let chars=content.count
        let hint=mode==0 ? "Markdown" : mode==1 ? "Opgemaakt · direct bewerkbaar" : "Naast elkaar · beide bewerkbaar"
        status.stringValue="\(words) woorden   ·   \(chars) tekens   ·   UTF-8   ·   \(hint)"
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        switch message.name {
        case "ready": ready=true;renderNow()
        case "changed":
            guard let info=message.body as? [String:Any], let value=info["markdown"] as? String,let incoming=info["revision"] as? Int,incoming==revision,let document=markdownDocument,value != document.content else {return}
            document.content=value;document.updateChangeCount(.changeDone)
            updating=true
            let selection=textView.selectedRange()
            textView.string=value
            textView.setSelectedRange(NSRange(location:min(selection.location,(value as NSString).length),length:0))
            updating=false;updateStatus()
        case "openLink":
            if let href=message.body as? String,let url=URL(string:href),["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case "error": NSLog("Markeer JavaScript error: %@",String(describing:message.body))
        default:break
        }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        if navigationAction.navigationType == .linkActivated {decisionHandler(.cancel)} else {decisionHandler(.allow)}
    }
    func isRichFocused()->Bool { guard let first=window?.firstResponder as? NSView else {return mode==1};return first===web || first.isDescendant(of:web) }
    func format(_ command:String,_ value:String="",prefix:String,suffix:String="") {
        if isRichFocused() {web.evaluateJavaScript("markeer.format(\(jsString(command)),\(jsString(value)))",completionHandler:nil)}
        else {
            let range=textView.selectedRange()
            let selection=(textView.string as NSString).substring(with:range)
            let replacement=prefix+selection+suffix
            textView.insertText(replacement,replacementRange:range)
            textView.setSelectedRange(NSRange(location:range.location+(prefix as NSString).length,length:(selection as NSString).length))
            window?.makeFirstResponder(textView)
        }
    }
    @objc func bold() {format("bold",prefix:"**",suffix:"**")}
    @objc func italic() {format("italic",prefix:"*",suffix:"*")}
    @objc func heading() {format("formatBlock","h2",prefix:"## ")}
    @objc func list() {format("insertUnorderedList",prefix:"- ")}
    @objc func numberedList() {
        if isRichFocused() {
            web.evaluateJavaScript("markeer.format('insertOrderedList')", completionHandler:nil)
        } else {
            let edit = MarkdownEditing.numberedList(in:textView.string, selection:textView.selectedRange())
            textView.insertText(edit.text, replacementRange:edit.range)
            window?.makeFirstResponder(textView)
        }
    }
    @objc func link() {
        let alert=NSAlert();alert.messageText="Link invoegen";alert.informativeText="Vul het webadres in. De geselecteerde tekst wordt de link."
        let field=NSTextField(frame:NSRect(x:0,y:0,width:350,height:26));field.stringValue="https://";alert.accessoryView=field
        alert.addButton(withTitle:"Invoegen");alert.addButton(withTitle:"Annuleren")
        guard alert.runModal() == .alertFirstButtonReturn,let url=URL(string:field.stringValue),["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") else {return}
        format("createLink",field.stringValue,prefix:"[",suffix:"](\(field.stringValue))")
    }
}
