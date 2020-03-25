//
//  ActiveType.swift
//  ActiveLabel
//
//  Created by Johannes Schickling on 9/4/15.
//  Copyright © 2015 Optonaut. All rights reserved.
//

import Foundation

enum ActiveElement: Hashable {
    case mention(String)
    case hashtag(String)
    case url(original: String, trimmed: String)
    case custom(String)

    static func create(with activeType: ActiveType, text: String) -> ActiveElement {
        switch activeType {
        case .mention: return mention(text)
        case .hashtag: return hashtag(text)
        case .url: return url(original: text, trimmed: text)
        case .custom, .customRange: return custom(text)
        }
    }
}

public enum ActiveType: Hashable {
    case mention
    case hashtag
    case url
    case custom(pattern: String)
    case customRange(NSRange)

    var pattern: String {
        switch self {
        case .mention: return RegexParser.mentionPattern
        case .hashtag: return RegexParser.hashtagPattern
        case .url: return RegexParser.urlPattern
        case .custom(let regex): return regex
        case .customRange(_): return ""
        }
    }
}
