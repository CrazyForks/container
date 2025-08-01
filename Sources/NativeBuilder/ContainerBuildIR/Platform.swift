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

import ContainerizationOCI
import Foundation

extension Platform {
    /// Linux on AMD64 (Intel/AMD 64-bit)
    public static let linuxAMD64 = Platform(arch: "amd64", os: "linux")

    /// Linux on ARM64 (64-bit ARM)
    public static let linuxARM64 = Platform(arch: "arm64", os: "linux")
}
