//
//  AdventureItem.swift
//  icfp06
//
//  Created by peter bohac on 12/31/19.
//  Copyright © 2019 peter bohac. All rights reserved.
//

import Foundation

struct AdventureItem: Equatable {
    enum Condition: Equatable {
        case pristine
        indirect case broken(condition: Condition, missing: [AdventureItem])

        init(sexp: Sexp) {
            if sexp.tag == "pristine" {
                self = .pristine
            } else if sexp.tag == "broken" {
                let condition = Condition(sexp: sexp.values.first { $0.tag == "condition" }!.values.first!)
                var missing: [AdventureItem] = []
                var queue = sexp.values.first { $0.tag == "missing" }!.values
                while queue.isEmpty == false {
                    let sexp = queue.removeFirst()
                    if sexp.tag == "kind" { missing.append(AdventureItem(sexp: sexp)) }
                    else { queue += sexp.values }
                }
                self = .broken(condition: condition, missing: missing)
            } else {
                preconditionFailure()
            }
        }
    }

    let name: String
    let adjective: String?
    var condition: Condition

    var fullName: String {
        if let adj = adjective { return "\(adj) \(name)" }
        else { return name }
    }

    func matches(_ other: AdventureItem) -> Bool {
        let nameMatches = self.name == other.name
        let conditionMatches = self.condition == other.condition
        return nameMatches && conditionMatches
    }

    mutating func combine(with item: AdventureItem) {
        guard case .broken(let condition, var missing) = self.condition else {
            preconditionFailure()
        }
        guard missing.removeFirst(where: { $0.matches(item) }) != nil else {
            preconditionFailure()
        }
        if missing.isEmpty {
            self.condition = condition
        } else {
            self.condition = .broken(condition: condition, missing: missing)
        }
    }
}

extension AdventureItem {
    init(sexp: Sexp) {
        assert((sexp.tag == "item" || sexp.tag == "kind") && sexp.values.isEmpty == false)
        var name: String!
        var adjective: String?
        var condition: Condition!

        for value in sexp.values {
            if value.tag == "name" {
                name = value.value!
            } else if value.tag == "adjectives" {
                var adj = value.values.first
                while adj != nil {
                    if adj!.tag == "adjective" {
                        adjective = adj!.value!
                        break
                    }
                    adj = adj?.values.first
                }
            } else if value.tag == "condition" {
                condition = Condition(sexp: value.values.first!)
            }
        }

        self.name = name
        self.adjective = adjective
        self.condition = condition
    }
}
