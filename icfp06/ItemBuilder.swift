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
        let output = executeCommand("switch goggles sexp", showingOutput: false)
        assert(Sexp(rawValue: output).tag == "success")
        defer {
            executeCommand("switch goggles English", showingOutput: false)
        }

        let itemStack = getRoom()
        let inventory = getInventory()

        print("*** Required items: ", terminator: "")
        guard let requiredItems = build(itemName, with: itemStack) else {
            print("*** Error! \(itemName) cannot be built.")
            return
        }
        print(requiredItems.map { $0.name }.joined(separator: ", "))

        print("Searching for solution...")
        if let solution = solve(targetName: itemName, inventory: inventory, parts: itemStack, requiredItems: requiredItems) {
            print("*** \(solution.count) steps:")
            print(solution.map { $0.description }.joined(separator: "\n"))
            print("")

            print("Perform build steps? (y/n): ", terminator: "")
            if let line = readLine(), line.lowercased() == "y" {
                executeCommand("switch goggles English", showingOutput: false)
                for action in solution {
                    executeCommand(action.description)
                }
            }
        } else {
            print("*** Unable to build \(itemName)")
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

    private func solve(targetName: String, inventory: [AdventureItem], parts: [AdventureItem], requiredItems: [AdventureItem]) -> [Action]? {
        let items = parts.filter { $0.name.lowercased() == targetName.lowercased() }
        let solutions = items.compactMap { item -> [Action]? in
            let targetItem = AdventureItem(name: item.name, adjective: nil, condition: .pristine)
            return solve(targetItem: targetItem, inventory: inventory, parts: parts, requiredItems: requiredItems)
        }
        return solutions.min { $0.count < $1.count }
    }

    private func solve(targetItem: AdventureItem, inventory: [AdventureItem], parts: [AdventureItem], requiredItems: [AdventureItem]) -> [Action]? {

        var inventory = inventory
        var parts = parts
        var requiredItems = requiredItems
        var actions: [Action] = []

        while requiredItems.isEmpty == false && parts.isEmpty == false {
            if inventory.count < 6 {
                let topItem = parts[0]
                var action = Action.take(topItem)
                action.apply(inventory: &inventory, parts: &parts)
                actions.append(action)

                if parts.filter({ $0.matches(topItem) }).count >= requiredItems.filter({ $0.matches(topItem) }).count {
//                if requiredItems.filter({ $0.matches(topItem) }).count == 0 { // uncomment this to build the MOSFET
                    action = .incinerate(topItem)
                    action.apply(inventory: &inventory, parts: &parts)
                    actions.append(action)
                } else {
                    requiredItems.removeFirst { $0.matches(topItem) }
                    reduceInventory: while true {
                        for item in inventory {
                            for missingItem in item.condition.missing {
                                if let found = inventory.first(where: { $0.matches(missingItem) }) {
                                    action = .combine(item, found)
                                    action.apply(inventory: &inventory, parts: &parts)
                                    actions.append(action)
                                    continue reduceInventory
                                }
                            }
                        }
                        break
                    }
                }
            } else {
                let candidates = inventory.compactMap { item -> (item: AdventureItem, requires: [AdventureItem], index: Int)? in
                    guard let requires = build(item, with: parts) else { return nil }
                    let index = requires.map { r in parts.lastIndex { $0.matches(r) }! }.max()!
                    return (item, requires, index)
                }
                guard let candidate = candidates.max(by: { $0.index < $1.index } ) else {
                    print("*** Error! Inventory is full.")
                    return nil
                }
                let action = Action.incinerate(candidate.item)
                action.apply(inventory: &inventory, parts: &parts)
                requiredItems += candidate.requires
                actions.append(action)
            }
        }

        return actions
    }

    private func build(_ targetName: String, with parts: [AdventureItem]) -> [AdventureItem]? {
        guard let name = parts.first(where: { $0.name.lowercased() == targetName.lowercased() })?.name else {
            return nil
        }
        let targetItem = AdventureItem(name: name, adjective: nil, condition: .pristine)
        return build(targetItem, with: parts)
    }

    private func build(_ targetItem: AdventureItem, with parts: [AdventureItem]) -> [AdventureItem]? {
        let possibleRoomItems = parts.filter { $0.name == targetItem.name }
        let possibleBuilds = possibleRoomItems.compactMap { item -> [AdventureItem]? in
            return build(targetItem, using: item, with: parts)
        }
        guard let bestBuild = possibleBuilds.min(by: { $0.count < $1.count }) else {
            return nil
        }
        return bestBuild
    }

    private func build(_ targetItem: AdventureItem, using roomItem: AdventureItem, with parts: [AdventureItem]) -> [AdventureItem]? {
        var remainingParts = parts.removingFirst { $0.matches(roomItem) }
        var requiredItems: [AdventureItem] = [roomItem]
        let targetItemMissing = targetItem.condition.missing
        var sourceItem = roomItem
        while sourceItem.matches(targetItem) == false {
            var combined = false
            for missingItem in sourceItem.condition.missing {
                if targetItemMissing.contains(where: { $0.matches(missingItem) }) {
                    continue
                }
                let exactItems = remainingParts.filter { $0.matches(missingItem) }
                if exactItems.isEmpty {
                    let possibleRoomItems = remainingParts.filter { $0.name == missingItem.name }
                    let possibleBuilds = possibleRoomItems.compactMap { item -> [AdventureItem]? in
                        return build(missingItem, using: item, with: remainingParts)
                    }
                    guard let bestBuild = possibleBuilds.min(by: { $0.count < $1.count }) else {
                        return nil
                    }
                    requiredItems += bestBuild
                    for item in bestBuild {
                        remainingParts.removeFirst { $0.matches(item) }
                    }
                } else {
                    let exactItem = exactItems.first!
                    requiredItems.append(exactItem)
                    remainingParts.removeFirst { $0.matches(exactItem) }
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
    private func executeCommand(_ command: String, showingOutput: Bool = true) -> String {
        print(command)
        inputBuffer = (command + "\n").utf8.map(Int.init).reversed()
        outputBuffer = ""
        showOutput = showingOutput
        um.run()
        let lines = outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        return lines.first(where: { $0.hasPrefix("(") }) ?? outputBuffer
    }

    private enum Action: CustomStringConvertible {
        case take(AdventureItem)
        case incinerate(AdventureItem)
        case combine(AdventureItem, AdventureItem)

        var description: String {
            switch self {
            case .take(let item): return "take \(item.fullName)"
            case .incinerate(let item): return "incinerate \(item.fullName)"
            case .combine(let left, let right): return "combine \(left.fullName) \(right.fullName)"
            }
        }

        func apply(inventory: inout [AdventureItem], parts: inout [AdventureItem]) {
            switch self {
            case .take(let item):
                assert(inventory.count < 6)
                assert(item == parts.first)
                inventory.append(parts.removeFirst())

            case .incinerate(let item):
                guard inventory.removeFirst(where: { $0.fullName == item.fullName }) != nil else {
                    preconditionFailure()
                }

            case .combine(let left, let right):
                guard let rightItem = inventory.removeFirst(where: { $0.fullName == right.fullName }) else {
                    preconditionFailure()
                }
                guard let leftIndex = inventory.firstIndex(where: { $0.fullName == left.fullName }) else {
                    preconditionFailure()
                }
                inventory[leftIndex].combine(with: rightItem)
            }
        }
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
