//
//  ActiveLabel.swift
//  ActiveLabel
//
//  Created by Johannes Schickling on 9/4/15.
//  Copyright © 2015 Optonaut. All rights reserved.
//

import Foundation
import UIKit

public protocol ActiveLabelDelegate: class {
    func didSelect(_ text: String, type: ActiveType, range: NSRange)
    func didLongTap(_ text: String, type: ActiveType, range: NSRange)
}

public typealias ConfigureLinkAttribute = (ActiveType, [NSAttributedString.Key : Any], Bool) -> ([NSAttributedString.Key : Any])
typealias ElementTuple = (range: NSRange, element: ActiveElement, type: ActiveType)

@IBDesignable open class ActiveLabel: UILabel {
    
    // MARK: - public properties
    open weak var delegate: ActiveLabelDelegate?

    open var enabledTypes: [ActiveType] = [.mention, .hashtag, .url]

    open var urlMaximumLength: Int?
    
    open var configureLinkAttribute: ConfigureLinkAttribute?
    
    open var fuzzyHeightMatching: Bool = false

    @IBInspectable open var mentionColor: UIColor = .blue {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable open var mentionSelectedColor: UIColor? {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable open var hashtagColor: UIColor = .blue {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable open var hashtagSelectedColor: UIColor? {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable open var URLColor: UIColor = .blue {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable open var URLSelectedColor: UIColor? {
        didSet { updateTextStorage(parseText: false) }
    }
    open var customColor: [ActiveType : UIColor] = [:] {
        didSet { updateTextStorage(parseText: false) }
    }
    open var customSelectedColor: [ActiveType : UIColor] = [:] {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable public var lineSpacing: CGFloat = 0 {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable public var minimumLineHeight: CGFloat = 0 {
        didSet { updateTextStorage(parseText: false) }
    }
    @IBInspectable public var highlightFontName: String? = nil {
        didSet { updateTextStorage(parseText: false) }
    }
    public var highlightFontSize: CGFloat? = nil {
        didSet { updateTextStorage(parseText: false) }
    }
    
    // MARK: - Computed Properties
    private var hightlightFont: UIFont? {
        guard let highlightFontName = highlightFontName, let highlightFontSize = highlightFontSize else { return nil }
        return UIFont(name: highlightFontName, size: highlightFontSize)
    }

    // MARK: - public methods
    open func handleMentionTap(_ handler: @escaping (String, NSRange) -> ()) {
        mentionTapHandler = handler
    }

    open func handleHashtagTap(_ handler: @escaping (String, NSRange) -> ()) {
        hashtagTapHandler = handler
    }
    
    open func handleURLTap(_ handler: @escaping (URL, NSRange) -> ()) {
        urlTapHandler = handler
    }

    open func handleCustomTap(for type: ActiveType, handler: @escaping (String, NSRange) -> ()) {
        customTapHandlers[type] = handler
    }

    open func handleCustomLongTap(for type: ActiveType, handler: @escaping (String, NSRange) -> ()) {
        customLongTapHandlers[type] = handler
    }
	
    open func removeHandle(for type: ActiveType) {
        switch type {
        case .hashtag:
            hashtagTapHandler = nil
        case .mention:
            mentionTapHandler = nil
        case .url:
            urlTapHandler = nil
        case .custom, .customRange:
            customTapHandlers[type] = nil
        }
    }

    open func removeAllHanders() {
        hashtagTapHandler = nil
        mentionTapHandler = nil
        urlTapHandler = nil
        customTapHandlers = [:]
    }

    open func filterMention(_ predicate: @escaping (String) -> Bool) {
        mentionFilterPredicate = predicate
        updateTextStorage()
    }

    open func filterHashtag(_ predicate: @escaping (String) -> Bool) {
        hashtagFilterPredicate = predicate
        updateTextStorage()
    }

    // MARK: - override UILabel properties
    override open var text: String? {
        didSet { updateTextStorage() }
    }

    override open var attributedText: NSAttributedString? {
        didSet { updateTextStorage() }
    }
    
    override open var font: UIFont! {
        didSet { updateTextStorage(parseText: false) }
    }
    
    override open var textColor: UIColor! {
        didSet { updateTextStorage(parseText: false) }
    }
    
    override open var textAlignment: NSTextAlignment {
        didSet { updateTextStorage(parseText: false)}
    }

    open override var numberOfLines: Int {
        didSet { textContainer.maximumNumberOfLines = numberOfLines }
    }

    open override var lineBreakMode: NSLineBreakMode {
        didSet { textContainer.lineBreakMode = lineBreakMode }
    }

    // MARK: - init functions
    override public init(frame: CGRect) {
        super.init(frame: frame)
        _customizing = false
        setupLabel()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        _customizing = false
        setupLabel()
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        updateTextStorage()
    }

    open override func drawText(in rect: CGRect) {
        let range = NSRange(location: 0, length: textStorage.length)

        textContainer.size = rect.size
        let newOrigin = textOrigin(inRect: rect)

        layoutManager.drawBackground(forGlyphRange: range, at: newOrigin)
        layoutManager.drawGlyphs(forGlyphRange: range, at: newOrigin)
    }


    // MARK: - customzation
    @discardableResult
    open func customize(_ block: (_ label: ActiveLabel) -> ()) -> ActiveLabel {
        _customizing = true
        block(self)
        _customizing = false
        updateTextStorage()
        return self
    }

    // MARK: - Auto layout

    open override var intrinsicContentSize: CGSize {
        textContainer.size = CGSize(width: self.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude)
        let size = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    // MARK: - touch events
    func onTouch(_ touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        var avoidSuperCall = false

        // Manage long tap timer
        if touch.phase == .began {
            beginLongTapTimer(location: location)
        } else if touch.phase != .moved {
            endLongTapTimer()
        }

        // Avoid simultaneous detection of regular tap and long tap:
        // If we have already detected a long tap, reset it and don't allow this touch to be detected as a regular tap
        // Else we will see regular tap behavior as soon as user lifts up the finger after a long tap
        if hasDetectedLongTap {
            return false
        }

        // Manage regular tap

        switch touch.phase {
        case .began, .moved:
            if let element = element(at: location) {
                if element.range.location != selectedElement?.range.location || element.range.length != selectedElement?.range.length {
                    updateAttributesWhenSelected(false)
                    selectedElement = element
                    updateAttributesWhenSelected(true)
                }
                avoidSuperCall = true
            } else {
                updateAttributesWhenSelected(false)
                selectedElement = nil
            }
        case .ended:
            guard let selectedElement = selectedElement else { return avoidSuperCall }

            switch selectedElement.element {
            case .mention(let userHandle): didTapMention(userHandle, range: selectedElement.range)
            case .hashtag(let hashtag): didTapHashtag(hashtag, range: selectedElement.range)
            case .url(let originalURL, _): didTapStringURL(originalURL, range: selectedElement.range)
            case .custom(let element): didTap(element, for: selectedElement.type, range: selectedElement.range)
            }
            
            let when = DispatchTime.now() + Double(Int64(0.25 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: when) {
                self.updateAttributesWhenSelected(false)
                self.selectedElement = nil
            }
            avoidSuperCall = true
        case .cancelled:
            updateAttributesWhenSelected(false)
            selectedElement = nil
        default:
            break
        }

        return avoidSuperCall
    }

    override open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var hitFrame = self.bounds
        if fuzzyHeightMatching {
            let hitTestEdgeInsets = UIEdgeInsets(top: -heightCorrection, left: 0, bottom: -heightCorrection, right: 0)
            hitFrame = hitFrame.inset(by: hitTestEdgeInsets)
        }
        return hitFrame.contains(point)
    }

    // MARK: - Long tap handling
    private func beginLongTapTimer(location: CGPoint) {
        hasDetectedLongTap = false
        longTapLocation = location
        longTapTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(fireLongTapEvent), userInfo: nil, repeats: false)
    }

    private func endLongTapTimer() {
        longTapTimer?.invalidate()
        longTapTimer = nil
    }

    @objc private func fireLongTapEvent() {
        if let location = longTapLocation,
            let selectedElement = element(at: location),
            case let .custom(string) = selectedElement.element {
            hasDetectedLongTap = true
            didLongTap(string, for: selectedElement.type, range: selectedElement.range)
        }
    }

    // MARK: - private properties
    fileprivate var _customizing: Bool = true
    fileprivate var defaultCustomColor: UIColor = .black
    
    internal var mentionTapHandler: ((String, NSRange) -> ())?
    internal var hashtagTapHandler: ((String, NSRange) -> ())?
    internal var urlTapHandler: ((URL, NSRange) -> ())?
    internal var customTapHandlers: [ActiveType : ((String, NSRange) -> ())] = [:]
    internal var customLongTapHandlers: [ActiveType : ((String, NSRange) -> ())] = [:]
    
    fileprivate var mentionFilterPredicate: ((String) -> Bool)?
    fileprivate var hashtagFilterPredicate: ((String) -> Bool)?

    fileprivate var selectedElement: ElementTuple?
    fileprivate var heightCorrection: CGFloat = 0
    internal lazy var textStorage = NSTextStorage()
    fileprivate lazy var layoutManager = NSLayoutManager()
    fileprivate lazy var textContainer = NSTextContainer()
    lazy var activeElements = [ActiveType: [ElementTuple]]()

    var longTapTimer: Timer?
    var longTapLocation: CGPoint?
    var hasDetectedLongTap: Bool = false

    // MARK: - helper functions
    
    fileprivate func setupLabel() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = lineBreakMode
        textContainer.maximumNumberOfLines = numberOfLines
        isUserInteractionEnabled = true
    }

    fileprivate func updateTextStorage(parseText: Bool = true) {
        if _customizing { return }
        // clean up previous active elements
        guard let attributedText = attributedText, attributedText.length > 0 else {
            clearActiveElements()
            textStorage.setAttributedString(NSAttributedString())
            setNeedsDisplay()
            return
        }

        let mutAttrString = NSMutableAttributedString(attributedString: addLineBreak(attributedText))

        // If the string changes in length, then we need to reset the string (because the attributes have changed indexes)
        // Otherwise, we can use the attributed string as is
        var removeAttributes = false

        if parseText {
            clearActiveElements()
            let newString = parseTextAndExtractActiveElements(mutAttrString)
            if newString.count != mutAttrString.string.count {
                mutAttrString.mutableString.setString(newString)
                removeAttributes = true
            }
        }

        addLinkAttribute(mutAttrString)
        textStorage.setAttributedString(mutAttrString)
        _customizing = true
        if removeAttributes {
            text = mutAttrString.string
        }
        _customizing = false
        setNeedsDisplay()
    }

    fileprivate func clearActiveElements() {
        selectedElement = nil
        for (type, _) in activeElements {
            activeElements[type]?.removeAll()
        }
    }

    fileprivate func textOrigin(inRect rect: CGRect) -> CGPoint {
        let usedRect = layoutManager.usedRect(for: textContainer)
        heightCorrection = (rect.height - usedRect.height)/2
        let glyphOriginY = heightCorrection > 0 ? rect.origin.y + heightCorrection : rect.origin.y
        return CGPoint(x: rect.origin.x, y: glyphOriginY)
    }

    /// add link attribute
    fileprivate func addLinkAttribute(_ mutAttrString: NSMutableAttributedString) {
        var range = NSRange(location: 0, length: 0)
        var attributes = mutAttrString.attributes(at: 0, effectiveRange: &range)
        
        attributes[NSAttributedString.Key.font] = font!
        attributes[NSAttributedString.Key.foregroundColor] = textColor
        mutAttrString.addAttributes(attributes, range: range)

        attributes[NSAttributedString.Key.foregroundColor] = mentionColor

        for (type, elements) in activeElements {

            switch type {
            case .mention: attributes[NSAttributedString.Key.foregroundColor] = mentionColor
            case .hashtag: attributes[NSAttributedString.Key.foregroundColor] = hashtagColor
            case .url: attributes[NSAttributedString.Key.foregroundColor] = URLColor
            case .custom, .customRange: attributes[NSAttributedString.Key.foregroundColor] = customColor[type] ?? defaultCustomColor
            }
            
            if let highlightFont = hightlightFont {
                attributes[NSAttributedString.Key.font] = highlightFont
            }
			
            if let configureLinkAttribute = configureLinkAttribute {
                attributes = configureLinkAttribute(type, attributes, false)
            }

            for element in elements {
                mutAttrString.setAttributes(attributes, range: element.range)
            }
        }
    }

    /// use regex check all link ranges
    fileprivate func parseTextAndExtractActiveElements(_ attrString: NSAttributedString) -> String {
        var textString = attrString.string
        var textLength = textString.utf16.count
        var textRange = NSRange(location: 0, length: textLength)

        if enabledTypes.contains(.url) {
            let tuple = ActiveBuilder.createURLElements(from: textString, range: textRange, maximumLength: urlMaximumLength)
            let urlElements = tuple.0
            let finalText = tuple.1
            textString = finalText
            textLength = textString.utf16.count
            textRange = NSRange(location: 0, length: textLength)
            activeElements[.url] = urlElements
        }

        for type in enabledTypes where type != .url {
            var filter: ((String) -> Bool)? = nil
            if type == .mention {
                filter = mentionFilterPredicate
            } else if type == .hashtag {
                filter = hashtagFilterPredicate
            }
            let hashtagElements = ActiveBuilder.createElements(type: type, from: textString, range: textRange, filterPredicate: filter)
            activeElements[type] = hashtagElements
        }

        return textString
    }


    /// add line break mode
    fileprivate func addLineBreak(_ attrString: NSAttributedString) -> NSMutableAttributedString {
        let mutAttrString = NSMutableAttributedString(attributedString: attrString)

        var range = NSRange(location: 0, length: 0)
        var attributes = mutAttrString.attributes(at: 0, effectiveRange: &range)
        
        let paragraphStyle = attributes[NSAttributedString.Key.paragraphStyle] as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = NSLineBreakMode.byWordWrapping
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.minimumLineHeight = minimumLineHeight > 0 ? minimumLineHeight: self.font.pointSize * 1.14
        attributes[NSAttributedString.Key.paragraphStyle] = paragraphStyle
        mutAttrString.setAttributes(attributes, range: range)

        return mutAttrString
    }

    fileprivate func updateAttributesWhenSelected(_ isSelected: Bool) {
        guard let selectedElement = selectedElement else {
            return
        }
        
        var attributes = textStorage.attributes(at: 0, effectiveRange: nil)
        let type = selectedElement.type

        if isSelected {
            let selectedColor: UIColor
            switch type {
            case .mention: selectedColor = mentionSelectedColor ?? mentionColor
            case .hashtag: selectedColor = hashtagSelectedColor ?? hashtagColor
            case .url: selectedColor = URLSelectedColor ?? URLColor
            case .custom, .customRange:
                let possibleSelectedColor = customSelectedColor[selectedElement.type] ?? customColor[selectedElement.type]
                selectedColor = possibleSelectedColor ?? defaultCustomColor
            }
            attributes[NSAttributedString.Key.foregroundColor] = selectedColor
        } else {
            let unselectedColor: UIColor
            switch type {
            case .mention: unselectedColor = mentionColor
            case .hashtag: unselectedColor = hashtagColor
            case .url: unselectedColor = URLColor
            case .custom, .customRange: unselectedColor = customColor[selectedElement.type] ?? defaultCustomColor
            }
            attributes[NSAttributedString.Key.foregroundColor] = unselectedColor
        }
        
        if let highlightFont = hightlightFont {
            attributes[NSAttributedString.Key.font] = highlightFont
        }
        
        if let configureLinkAttribute = configureLinkAttribute {
            attributes = configureLinkAttribute(type, attributes, isSelected)
        }

        textStorage.addAttributes(attributes, range: selectedElement.range)

        setNeedsDisplay()
    }

    fileprivate func element(at location: CGPoint) -> ElementTuple? {
        guard textStorage.length > 0 else {
            return nil
        }

        var correctLocation = location
        var boundingRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: 0, length: textStorage.length), in: textContainer)
        
        if fuzzyHeightMatching {
            boundingRect = boundingRect.insetBy(dx: 0, dy: -heightCorrection)
        } else {
            correctLocation.y -= heightCorrection
        }
        
        // Compare our touch location to the full height of the view
        guard boundingRect.contains(correctLocation) else {
            return nil
        }

        // Now that we've used the full heigt, figure out where the touch occured using the correct height
        if fuzzyHeightMatching {
            correctLocation.y -= heightCorrection
        }
        
        let index = layoutManager.glyphIndex(for: correctLocation, in: textContainer)
        
        for element in activeElements.map({ $0.1 }).joined() {
            if index >= element.range.location && index <= element.range.location + element.range.length {
                return element
            }
        }

        return nil
    }


    //MARK: - Handle UI Responder touches
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if onTouch(touch) { return }
        super.touchesBegan(touches, with: event)
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if onTouch(touch) { return }
        super.touchesMoved(touches, with: event)
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        _ = onTouch(touch)
        super.touchesCancelled(touches, with: event)
    }
    
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if onTouch(touch) { return }
        super.touchesEnded(touches, with: event)
    }

    //MARK: - ActiveLabel handler
    fileprivate func didTapMention(_ username: String, range: NSRange) {
        guard let mentionHandler = mentionTapHandler else {
            delegate?.didSelect(username, type: .mention, range: range)
            return
        }
        mentionHandler(username, range)
    }

    fileprivate func didTapHashtag(_ hashtag: String, range: NSRange) {
        guard let hashtagHandler = hashtagTapHandler else {
            delegate?.didSelect(hashtag, type: .hashtag, range: range)
            return
        }
        hashtagHandler(hashtag, range)
    }

    fileprivate func didTapStringURL(_ stringURL: String, range: NSRange) {
        guard let urlHandler = urlTapHandler, let url = URL(string: stringURL) else {
            delegate?.didSelect(stringURL, type: .url, range: range)
            return
        }
        urlHandler(url, range)
    }

    fileprivate func didTap(_ element: String, for type: ActiveType, range: NSRange) {
        guard let elementHandler = customTapHandlers[type] else {
            delegate?.didSelect(element, type: type, range: range)
            return
        }
        elementHandler(element, range)
    }

    fileprivate func didLongTap(_ element: String, for type: ActiveType, range: NSRange) {
        guard let elementHandler = customLongTapHandlers[type] else {
            delegate?.didLongTap(element, type: type, range: range)
            return
        }
        elementHandler(element, range)
    }
}

extension ActiveLabel: UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
