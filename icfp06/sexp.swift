//
//  sexp.swift
//  icfp06
//
//  Created by peter bohac on 12/30/19.
//  Copyright © 2019 peter bohac. All rights reserved.
//

import Foundation

enum Sexp: Equatable {
    case empty(tag: String)
    case expr(tag: String, value: String)
    case special(tag: String, value: String)
    indirect case list(tag: String, value: [Sexp])

    var tag: String {
        switch self {
        case .empty(let tag): return tag
        case .expr(let tag, _): return tag
        case .special(let tag, _): return tag
        case .list(let tag, _): return tag
        }
    }

    var value: String? {
        switch self {
        case .expr(_, let value): return value
        case .special(_, let value): return value
        case .empty, .list: return nil
        }
    }

    var values: [Sexp] {
        switch self {
        case .list(_, let value): return value
        case .empty, .expr, .special: return []
        }
    }

    var isEmpty: Bool {
        switch self {
        case .empty: return true
        case .expr, .special, .list: return false
        }
    }

    init(rawValue: String) {
        var input = rawValue
        assert(input.first == "(")
        input.removeFirst()
        self = Self.parse(&input)
        assert(input.isEmpty)
    }

    static func parse(_ input: inout String) -> Sexp {
        enum State {
            case parsingTag, finishedTag, parsingList, parsingString, parsingEscape, finishedString, parsingSpecial
        }

        var tag = ""
        var stringValue: String?
        var listValue: [Sexp] = []
        var state = State.parsingTag

        while input.isEmpty == false {
            let char = input.removeFirst()
            switch (state, char) {
            case (.parsingTag, " "):
                state = .finishedTag
            case (.parsingTag, ")"):
                preconditionFailure()
            case (.parsingTag, "("):
                state = .parsingList
                listValue.append(parse(&input))
            case (.parsingTag, _):
                tag.append(char)

            case (.finishedTag, "("):
                state = .parsingList
                listValue.append(parse(&input))
            case (.finishedTag, "\""):
                state = .parsingString
                stringValue = ""
            case (.finishedTag, ")"):
                return .empty(tag: tag)
            case (.finishedTag, _):
                state = .parsingSpecial
                stringValue = ""

            case (.parsingList, "("):
                listValue.append(parse(&input))
            case (.parsingList, " "):
                continue
            case (.parsingList, ")"):
                return .list(tag: tag, value: listValue)
            case (.parsingList, _):
                preconditionFailure()

            case (.parsingString, "\\"):
                state = .parsingEscape
            case (.parsingString, "\""):
                state = .finishedString
            case (.parsingString, _):
                stringValue?.append(char)

            case (.parsingEscape, "\""):
                stringValue?.append(char)
                state = .parsingString
            case (.parsingEscape, _):
                preconditionFailure()

            case (.finishedString, ")"):
                return .expr(tag: tag, value: stringValue!)
            case (.finishedString, _):
                preconditionFailure()

            case (.parsingSpecial, ")"):
                return .special(tag: tag, value: stringValue!)
            case (.parsingSpecial, _):
                stringValue?.append(char)
            }
        }
        preconditionFailure()
    }
}
