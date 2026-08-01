/**
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
/**
 * Notice: I (Jamie Sinclair) have modified this file.
 * Updated to support a partial subset of Avif encoding options to be provided.
 * The avif options are defaulted to defaults from the meta.ts file.
 */
import type { EncodeOptions, ImageData16bit } from './meta.js';
export declare function init(moduleOptionOverride?: Partial<EmscriptenWasm.ModuleOpts>): Promise<any>;
export default function encode(data: ImageData): Promise<ArrayBuffer>;
export default function encode(data: ImageData, options: Partial<EncodeOptions> & {
    bitDepth?: 8;
}): Promise<ArrayBuffer>;
export default function encode(data: ImageData16bit, options: Partial<EncodeOptions> & {
    bitDepth: 10 | 12;
}): Promise<ArrayBuffer>;
//# sourceMappingURL=encode.d.ts.map