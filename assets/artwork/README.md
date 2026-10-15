# Launcher poster

`launcher_poster.png` is the single presentation image extracted at the user's request from the PvZGE Lite 0.15.0 resource, not a game resource payload.

- Source: `assets/resources/native/1a/1aae2f737.avif`, 2054 × 3084.
- Source SHA-256: `10809f8fafaf7cb863df95e9187df95c6bfe1c2c0a70733c65cb758b2db5bdf1`.
- Crop: `(4, 6, 2048, 1536)`, with right and bottom exclusive, matching the launcher's previous top-poster crop.
- Output: RGB PNG, 1600 × 1198; PNG SHA-256: `142b748f42b9fd6846275037d5d23acfa567ea917a88dbd82cb1d3bcb2ee375a`.
- Extraction: Pillow 12.1.1, `Image.open(source).crop((4, 6, 2048, 1536)).convert('RGB').resize((1600, 1198), Image.Resampling.LANCZOS).save(output, optimize=True)`.

The launcher uses this one bundled asset on Android, iOS and HarmonyOS, including before resource import. Builds do not download, extract or decode game textures. The existing framing and scrims remain in `KeyArtBackdrop`.
