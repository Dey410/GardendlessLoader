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
import { initEmscriptenModule } from './utils.js';
import avif_dec from './codec/dec/avif_dec.js';
let emscriptenModule;
export async function init(module, moduleOptionOverrides) {
    let actualModule = module;
    let actualOptions = moduleOptionOverrides;
    // If only one argument is provided and it's not a WebAssembly.Module
    if (arguments.length === 1 && !(module instanceof WebAssembly.Module)) {
        actualModule = undefined;
        actualOptions = module;
    }
    emscriptenModule = initEmscriptenModule(avif_dec, actualModule, actualOptions);
}
export default async function decode(buffer, options) {
    var _a;
    if (!emscriptenModule) {
        init();
    }
    const module = await emscriptenModule;
    const bitDepth = (_a = options === null || options === void 0 ? void 0 : options.bitDepth) !== null && _a !== void 0 ? _a : 8;
    const result = module.decode(buffer, bitDepth);
    if (!result)
        throw new Error('Decoding error');
    return result;
}
