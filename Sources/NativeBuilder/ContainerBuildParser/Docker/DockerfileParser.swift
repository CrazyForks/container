//===----------------------------------------------------------------------===//
// Copyright © 2025 Apple Inc. and the container project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerBuildIR
import Foundation

/// DockerfileParser parses a dockerfile to a BuildGraph.
public struct DockerfileParser: BuildParser {
    public func parse(_ input: String) throws -> BuildGraph {
        var instructions = [DockerInstruction]()
        let lines = input.components(separatedBy: .newlines)
        var lineIndex = 0
        while lineIndex < lines.count {
            var line = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                lineIndex += 1
                continue
            }

            while lineIndex < lines.count && line.hasSuffix("\\") {
                line = String(line.dropLast("\\".count))
                let next = lineIndex + 1
                if next < lines.count {
                    let nextLine = String(lines[next].trimmingCharacters(in: .whitespacesAndNewlines))
                    line.append(nextLine)
                    lineIndex += 1
                }
            }

            var tokenizer = DockerfileTokenizer(line)
            let tokens = try tokenizer.getTokens()

            try instructions.append(tokensToDockerInstruction(tokens: tokens))

            lineIndex += 1
        }
        let visitor = DockerInstructionVisitor()
        return try visitor.buildGraph(from: instructions)
    }

    private func tokensToDockerInstruction(tokens: [Token]) throws -> DockerInstruction {
        guard case .stringLiteral(let value) = tokens.first else {
            throw ParseError.missingInstruction
        }

        let instruction = DockerInstructionName(rawValue: value.lowercased())

        switch instruction {
        case .FROM:
            return try tokensToFromInstruction(tokens: tokens)
        case .RUN:
            return try tokensToRunInstruction(tokens: tokens)
        default:
            throw ParseError.invalidInstruction(value)
        }
    }

    internal func tokensToFromInstruction(tokens: [Token]) throws -> FromInstruction {
        var index = tokens.startIndex
        index += 1  // skip the instruction

        var stageName: String?
        var platform: String?
        var imageName: String?

        // Step 1: parse options
        while index < tokens.endIndex {
            guard case .option(let key, let value) = tokens[index] else {
                break
            }
            guard FromOptions(rawValue: key) == .platform else {
                throw ParseError.unexpectedValue
            }
            platform = value
            index += 1
        }

        // Step 2: Parse image name
        if index < tokens.endIndex {
            guard case .stringLiteral(let value) = tokens[index] else {
                throw ParseError.unexpectedValue
            }
            imageName = value
            index += 1
        }

        // Step 3 (optional): Parse stage name
        if index < tokens.endIndex {
            guard case .stringLiteral(let value) = tokens[index],
                DockerKeyword(rawValue: value.lowercased()) == .AS
            else {
                throw ParseError.unexpectedValue
            }
            index += 1
            guard index < tokens.endIndex, case .stringLiteral(let name) = tokens[index] else {
                throw ParseError.invalidSyntax
            }
            stageName = name
            index += 1
        }

        guard let imageName = imageName else {
            throw ParseError.invalidSyntax
        }

        // check for extra tokens
        if index < tokens.endIndex {
            throw ParseError.unexpectedValue
        }

        return try FromInstruction(image: imageName, platform: platform, stageName: stageName)
    }

    internal func tokensToRunInstruction(tokens: [Token]) throws -> RunInstruction {
        var index = tokens.startIndex
        index += 1  // skip the instruction

        var rawMounts = [String]()
        var network: String? = nil

        // Step 1: parse options
        while index < tokens.endIndex {
            guard case .option(let key, let value) = tokens[index] else {
                break
            }

            guard let option = RunOptions(rawValue: key) else {
                throw ParseError.unexpectedValue
            }

            switch option {
            case .mount:
                rawMounts.append(value)
            case .network:
                network = value
            default:
                throw ParseError.unexpectedValue
            }
            index += 1
        }

        var command = [String]()
        var shell = true

        // Step 2: parse run command and if we're using shell or exec form
        while index < tokens.endIndex {
            if case .stringList(let value) = tokens[index], command.isEmpty {
                // when using the exec form, there should only be a single list for the command
                // if there's other content in the command already, the input was invalid
                command = value
                shell = false
                index += 1
                break
            } else if case .stringLiteral(let value) = tokens[index] {
                command.append(value)
            } else {
                break
            }
            index += 1
        }

        // check for extra tokens
        if index < tokens.endIndex {
            throw ParseError.unexpectedValue
        }

        return try RunInstruction(command: command, shell: shell, rawMounts: rawMounts, network: network)
    }

    internal func tokensToCopyInstruction(tokens: [Token]) throws -> CopyInstruction {
        var index = tokens.startIndex
        index += 1  // skip the instruction

        var from: String? = nil
        var chmod: String? = nil
        var chown: String? = nil
        var link: String? = nil

        // Step 1: parse options
        while index < tokens.endIndex {
            guard case .option(let key, let value) = tokens[index] else {
                break
            }

            guard let option = CopyOptions(rawValue: key) else {
                throw ParseError.unexpectedValue
            }

            switch option {
            case .from:
                if from != nil {
                    throw ParseError.duplicateOptionSet(CopyOptions.from.rawValue)
                }
                from = value
            case .chown:
                if chown != nil {
                    throw ParseError.duplicateOptionSet(CopyOptions.chown.rawValue)
                }
                chown = value
            case .chmod:
                if chmod != nil {
                    throw ParseError.duplicateOptionSet(CopyOptions.chmod.rawValue)
                }
                chmod = value
            case .link:
                if link != nil {
                    throw ParseError.duplicateOptionSet(CopyOptions.link.rawValue)
                }
                link = value
            default:
                throw ParseError.unexpectedValue
            }
            index += 1
        }

        // Step 2: Get all source paths and destination path
        var sources: [String] = []
        var destination: String?
        while index < tokens.endIndex {
            guard case .stringLiteral(let value) = tokens[index] else {
                break
            }
            if index + 1 == tokens.endIndex {
                // this is the last path provided, it must be the destination
                destination = value
            } else {
                sources.append(value)
            }
            index += 1
        }

        // check for extra tokens
        if index < tokens.endIndex {
            throw ParseError.unexpectedValue
        }

        return try CopyInstruction(sources: sources, destination: destination, from: from, ownership: chown, permissions: chmod)
    }

}
