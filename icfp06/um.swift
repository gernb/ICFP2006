//
//  um.swift
//  icfp06
//
//  Created by peter bohac on 12/28/19.
//  Copyright © 2019 peter bohac. All rights reserved.
//

import Foundation

final class UM {
    private let inputProvider: (() -> Int?)
    private let outputHandler: ((Int) -> Bool)

    private var ip: Int
    private var register: [Int]
    private var platterArrays: [Int: [Int]]
    private var nextPlatterIndex: Int

    typealias State = [Int: [Int]]
    var state: State {
        get { [ -1: [ip], -2: register ].merging(platterArrays) { _, _ in preconditionFailure() } }
        set {
            ip = newValue[-1]![0]
            register = newValue[-2]!
            platterArrays = newValue
            platterArrays.removeValue(forKey: -1)
            platterArrays.removeValue(forKey: -2)
            nextPlatterIndex = platterArrays.keys.max()! + 1
        }
    }

    enum Status {
        case halted
        case inputNeeded
        case stopRequested
        case invalidInstruction
        case timeExpired
    }

    init(program: [Int], input: @escaping (() -> Int?), output: @escaping ((Int) -> Bool)) {
        self.inputProvider = input
        self.outputHandler = output
        self.ip = 0
        self.register = Array(repeating: 0, count: 8)
        self.platterArrays = [0: program]
        self.nextPlatterIndex = 1
    }

    @discardableResult
    func run(until time: DispatchTime = .distantFuture) -> Status {
        repeat {
            let instruction = platterArrays[0]![ip]
            let (op, A, B, C) = decode(instruction)

            switch op {
            case 0: // conditional move
                if register[C] != 0 {
                    register[A] = register[B]
                }
                ip += 1

            case 1: // array index
                let offset = register[C]
                register[A] = platterArrays[register[B]]![offset]
                ip += 1

            case 2: // array amendment
                let offset = register[B]
                platterArrays[register[A]]![offset] = register[C]
                ip += 1

            case 3: // addition
                register[A] = (register[B] + register[C]) % (1 << 32)
                ip += 1

            case 4: // multiplication
                register[A] = register[B].multipliedReportingOverflow(by: register[C]).partialValue % (1 << 32)
                ip += 1

            case 5: // division
                register[A] = Int(UInt32(register[B]) / UInt32(register[C]))
                ip += 1

            case 6: // not-and
                register[A] = ~(register[B] & register[C]) & 0xFFFFFFFF
                ip += 1

            case 7: // halt
                return .halted

            case 8: // allocation
                platterArrays[nextPlatterIndex] = Array(repeating: 0, count: register[C])
                register[B] = nextPlatterIndex
                nextPlatterIndex += 1
                ip += 1

            case 9: // abandonment
                platterArrays.removeValue(forKey: register[C])
                ip += 1

            case 10: // output
                let `continue` = outputHandler(register[C])
                ip += 1
                if `continue` == false {
                    return .stopRequested
                }

            case 11: // input
                guard let input = inputProvider() else {
                    return .inputNeeded
                }
                register[C] = input
                ip += 1

            case 12: // load program
                platterArrays[0] = platterArrays[register[B]]!
                ip = register[C]

            case 13: // orthography
                let a = (instruction >> 25) & 0x7
                let value = instruction & 0x1FFFFFF
                register[a] = value
                ip += 1

            default:
                return .invalidInstruction
            }
        } while DispatchTime.now() < time
        return .timeExpired
    }

    private func decode(_ instruction: Int) -> (op: Int, A: Int, B: Int, C: Int) {
        let op = (instruction >> 28) & 0xF
        let a = (instruction >> 6) & 0x7
        let b = (instruction >> 3) & 0x7
        let c = instruction & 0x7
        return (op, a, b, c)
    }
}
