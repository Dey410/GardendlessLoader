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
import { EncodeOptions as RawEncodeOptions, AVIFTune } from './codec/enc/avif_enc.js';
export { AVIFTune };
export type EncodeOptions = RawEncodeOptions & {
    lossless: boolean;
};
export type ImageData16bit = {
    data: Uint16Array;
    width: number;
    height: number;
};
export declare const label = "AVIF";
export declare const mimeType = "image/avif";
export declare const extension = "avif";
export declare const defaultOptions: EncodeOptions;
//# sourceMappingURL=meta.d.ts.map