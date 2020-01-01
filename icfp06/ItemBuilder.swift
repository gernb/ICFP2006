//
//  ItemBuilder.swift
//  icfp06
//
//  Created by peter bohac on 12/31/19.
//  Copyright © 2019 peter bohac. All rights reserved.
//

import Foundation

final class ItemBuilder {
    let itemName: String

    var inputBuffer: [Int] = []
    var outputBuffer = ""
    var showOutput = true
    var um: UM!

    init(build name: String, with state: UM.State) {
        self.itemName = name
        self.um = UM(program: [], input: { [unowned self] in self.inputBuffer.popLast() }) { [unowned self] value in
            let char = Character(UnicodeScalar(value)!)
            if self.showOutput { print(char, terminator: "") }
            self.outputBuffer.append(char)
            return true
        }
        self.um.state = state
    }

    func run() {
        let output = executeCommand("switch goggles sexp")
        assert(Sexp(rawValue: output).tag == "success")
        defer {
            executeCommand("switch goggles English")
        }

        var itemStack = getRoom()

        guard let sourceItem = itemStack.first(where: { $0.name.lowercased() == itemName.lowercased() }) else {
            print("*** Error! \(itemName) is not in this room.")
            return
        }
        let item = AdventureItem(name: sourceItem.name, adjective: nil, condition: .pristine)
        print("*** Required items: ", terminator: "")
        guard var requiredItems = build(item, using: sourceItem, with: itemStack) else {
            print("*** Error! \(itemName) cannot be built.")
            return
        }
        print(requiredItems.map { $0.name }.joined(separator: ", "))

        while requiredItems.isEmpty == false && itemStack.isEmpty == false {
            let topItem = itemStack.removeFirst()
            var result = Sexp(rawValue: executeCommand("take \(topItem.fullName)"))
            if result.tag != "success" {
                let inventory = getInventory()
                let candidates = inventory.compactMap { item -> (item: AdventureItem, requires: [AdventureItem], index: Int)? in
                    guard let requires = build(item, with: itemStack) else { return nil }
                    let index = requires.map { r in itemStack.lastIndex { $0.matches(r) }! }.max()!
                    return (item, requires, index)
                }
                guard let candidate = candidates.max(by: { $0.index < $1.index } ) else {
                    print("*** Error! Failed to take \(topItem.fullName).")
                    return
                }
                executeCommand("incinerate \(candidate.item.fullName)")
                requiredItems += candidate.requires
                executeCommand("take \(topItem.fullName)")
            }
            if requiredItems.removeFirst(where: { $0.fullName == topItem.fullName }) == nil {
                result = Sexp(rawValue: executeCommand("incinerate \(topItem.fullName)"))
                assert(result.tag == "success")
            } else {
                while reduceInventory() {}
            }
        }
    }

    private func getInventory() -> [AdventureItem] {
        let result = Sexp(rawValue: executeCommand("inventory", showingOutput: false))
        assert(result.tag == "success")
        var inventory: [AdventureItem] = []
        var queue: [Sexp] = [result]
        while queue.isEmpty == false {
            let sexp = queue.removeFirst()
            if sexp.tag == "item" {
                inventory.append(AdventureItem(sexp: sexp))
            } else {
                queue += sexp.values
            }
        }
        return inventory
    }

    private func getRoom() -> [AdventureItem] {
        var result = Sexp(rawValue: executeCommand("look", showingOutput: false))
        assert(result.tag == "success")
        var items: [AdventureItem] = []

        result = result.values.first!
        assert(result.tag == "command")
        result = result.values.first!
        assert(result.tag == "look")
        result = result.values.first!
        assert(result.tag == "room")
        result = result.values.first { $0.tag == "items" }!
        assert(result.values.count == 1)
        result = result.values.first!
        assert(result.values.count == 1 && result.tag == "")
        result = result.values.first!

        while true {
            assert(result.tag == "item")
            items.append(AdventureItem(sexp: result))
            result = result.values.first { $0.tag == "piled_on" }!
            if result.values.count == 0 {
                break
            }
            assert(result.values.count == 1)
            result = result.values.first!
            assert(result.values.count == 1 && result.tag == "")
            result = result.values.first!
        }

        return items
    }

    private func build(_ targetItem: AdventureItem, with parts: [AdventureItem]) -> [AdventureItem]? {
        let possibleRoomItems = parts.filter { $0.name == targetItem.name }
        let possibleBuilds = possibleRoomItems.compactMap { element -> [AdventureItem]? in
            return build(targetItem, using: element, with: parts)
        }
        guard let bestBuild = possibleBuilds.min(by: { $0.count < $1.count }) else {
            return nil
        }
        return bestBuild
    }

    private func build(_ targetItem: AdventureItem, using sourceItem: AdventureItem, with parts: [AdventureItem]) -> [AdventureItem]? {
        var remainingParts = parts.removingFirst { $0.matches(sourceItem) }
        var requiredItems: [AdventureItem] = [sourceItem]
        let targetItemMissing: [AdventureItem] = {
            switch targetItem.condition {
            case .pristine: return []
            case .broken(_, let missing): return missing
            }
        }()
        var sourceItem = sourceItem
        while sourceItem.matches(targetItem) == false {
            guard case .broken(_, let sourceItemMissing) = sourceItem.condition else {
                return nil
            }
            var combined = false
            for missingItem in sourceItemMissing {
                if targetItemMissing.contains(where: { $0.matches(missingItem) }) {
                    continue
                }
                if let exactItem = remainingParts.first(where: { $0.matches(missingItem) }) {
                    requiredItems.append(exactItem)
                    remainingParts.removeFirst { $0.matches(exactItem) }
                } else {
                    let possibleRoomItems = remainingParts.filter { $0.name == missingItem.name }
                    let possibleBuilds = possibleRoomItems.compactMap { element -> [AdventureItem]? in
                        return build(missingItem, using: element, with: remainingParts)
                    }
                    guard let bestBuild = possibleBuilds.min(by: { $0.count < $1.count }) else {
                        return nil
                    }
                    requiredItems += bestBuild
                    for item in bestBuild {
                        remainingParts.removeFirst { $0.matches(item) }
                    }
                }
                sourceItem.combine(with: missingItem)
                combined = true
            }
            if !combined {
                return nil
            }
        }
        return requiredItems
    }

    @discardableResult
    private func reduceInventory() -> Bool {
        let inventory = getInventory()
        for item in inventory.reversed() {
            if case .broken(_, let missing) = item.condition {
                for missingItem in missing {
                    if let found = inventory.first(where: { $0.matches(missingItem) }) {
                        let result = Sexp(rawValue: executeCommand("combine \(item.fullName) \(found.fullName)"))
                        if result.tag == "success" {
                            return true
                        } else {
                            assertionFailure()
                        }
                    }
                }
            }
        }
        return false
    }

    @discardableResult
    private func executeCommand(_ command: String, showingOutput: Bool = true) -> String {
        print(command)
        inputBuffer = (command + "\n").utf8.map(Int.init).reversed()
        outputBuffer = ""
        showOutput = showingOutput
        um.run()
        let lines = outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        return lines.first(where: { $0.hasPrefix("(") }) ?? outputBuffer
    }
}

extension Array {
    @discardableResult
    mutating func removeFirst(where filter: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try self.firstIndex(where: filter) else { return nil }
        return self.remove(at: index)
    }

    func removingFirst(where filter: (Element) throws -> Bool) rethrows -> [Element] {
        var result = self
        try result.removeFirst(where: filter)
        return result
    }
}
