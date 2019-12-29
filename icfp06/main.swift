//
//  main.swift
//  icfp06
//
//  Created by peter bohac on 12/28/19.
//  Copyright © 2019 peter bohac. All rights reserved.
//

import Foundation

var programFilename: String?
var savedStateFilename: String?
var outputFilename: String?
var disassemble = false
var unusedArgs: [String] = []
var arguments = CommandLine.arguments.dropFirst()
while arguments.isEmpty == false {
    let arg = arguments.removeFirst()
    if (arg == "--program" || arg == "-p") && arguments.count > 0 {
        programFilename = arguments.removeFirst()
    } else if (arg == "--load" || arg == "-l") && arguments.count > 0 {
        savedStateFilename = arguments.removeFirst()
    } else if (arg == "--output" || arg == "-o") && arguments.count > 0 {
        outputFilename = arguments.removeFirst()
    } else if arg == "--disassemble" {
        disassemble = true
    } else {
        if programFilename == nil {
            programFilename = arg
        } else if savedStateFilename == nil {
            savedStateFilename = arg
        } else {
            unusedArgs.append(arg)
        }
    }
}

guard unusedArgs.isEmpty, let programFilename = programFilename else {
    print("Usage: [--program] <program filename> [[--load] <saved state filename>]")
    exit(0)
}

let pwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let program: [Int] = {
    let inputFileUrl = pwd.appendingPathComponent(programFilename)
    let data = try! Data(contentsOf: inputFileUrl)
    var temp: [UInt32] = Array(repeating: 0, count: data.count / 4)
    _ = temp.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return temp.map { Int(UInt32(bigEndian: $0)) }
}()

var inputBuffer: [Int] = []
var dataBuffer: Data?
if outputFilename != nil {
    dataBuffer = Data()
}

let um = UM(program: program, input: { return inputBuffer.popLast() }) { value in
    print(Character(UnicodeScalar(value)!), terminator: "")
    dataBuffer?.append(UInt8(value))
    return true
}

let decoder = PropertyListDecoder()
var encoder = PropertyListEncoder()

func saveState(to filename: String) {
    let fileUrl = pwd.appendingPathComponent(filename)
    if let data = try? encoder.encode(um.state), (try? data.write(to: fileUrl)) != nil {
        print("\nSaved to \(filename)\n")
    }
}

func loadState(from filename: String) {
    let fileUrl = pwd.appendingPathComponent(filename)
    if let data = try? Data(contentsOf: fileUrl), let state = try? decoder.decode(UM.State.self, from: data) {
        um.state = state
        print("\nLoaded saved state from \(filename)\n")
    }
}

if let filename = savedStateFilename {
    loadState(from: filename)
}

if disassemble {
//    let disassembler = Disassembler(state: vm.state)
//    disassembler.disassemble()
    print("Not implemented yet")
    exit(0)
}

enum Input: Equatable {
    case quit
    case save(String)
    case load(String)
    case other(String)
}

func getInput(prompt: String? = nil) -> Input {
    if let prompt = prompt {
        print(prompt)
    }
    let line = readLine() ?? ""
    if line == "quit" {
        return .quit
    }
    if line.hasPrefix("save") {
        let file = String(line.dropFirst(5))
        if file.isEmpty {
            print("Usage: save <filename>")
            return getInput(prompt: prompt)
        }
        return .save(file)
    }
    if line.hasPrefix("load") {
        let file = String(line.dropFirst(5))
        if file.isEmpty {
            print("Usage: load <filename>")
            return getInput(prompt: prompt)
        }
        return .load(file)
    }
    return .other(line)
}

while true {
    let status = um.run()
    switch status {
    case .halted:
        print("\nExecution halted\n")
        if let filename = outputFilename {
            let fileUrl = pwd.appendingPathComponent(filename)
            try? dataBuffer?.write(to: fileUrl)
        }
        exit(0)

    case .inputNeeded:
        let input = getInput()
        if input == .quit {
            exit(0)
        } else if case .save(let filename) = input {
            saveState(to: filename)
        } else if case .load(let filename) = input {
            loadState(from: filename)
        } else if case .other(let line) = input {
            inputBuffer = (line + "\n").utf8.map(Int.init).reversed()
        } else {
            preconditionFailure()
        }

    case .stopRequested, .invalidInstruction, .timeExpired:
        preconditionFailure()
    }
}
