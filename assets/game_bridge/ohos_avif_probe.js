(function () {
  "use strict";

  const tag = "[DEBUG-a4f2]";
  const path = "assets/resources/native/6f/6f01cf7f-81bf-4a7e-bd5d-0afc19696480@b47c0@40c10.png";

  async function probe() {
    try {
      const response = await fetch(path, { cache: "no-store" });
      const bytes = await response.arrayBuffer();
      const header = response.headers.get("content-type") || "<missing>";
      const avif = new Blob([bytes], { type: "image/avif" });
      console.error(`${tag} fetch status=${response.status} header=${header} bytes=${bytes.byteLength}`);

      const imageUrl = URL.createObjectURL(avif);
      const element = new Image();
      element.onload = function () {
        console.error(`${tag} image=success width=${element.naturalWidth} height=${element.naturalHeight}`);
        URL.revokeObjectURL(imageUrl);
      };
      element.onerror = function () {
        console.error(`${tag} image=failure`);
        URL.revokeObjectURL(imageUrl);
      };
      element.src = imageUrl;

      if (typeof createImageBitmap === "function") {
        try {
          const bitmap = await createImageBitmap(avif);
          console.error(`${tag} imageBitmap=success width=${bitmap.width} height=${bitmap.height}`);
          bitmap.close();
        } catch (error) {
          console.error(`${tag} imageBitmap=failure message=${String(error && error.message || error)}`);
        }
      } else {
        console.error(`${tag} imageBitmap=unavailable`);
      }

      if (typeof ImageDecoder === "function" && typeof ImageDecoder.isTypeSupported === "function") {
        try {
          const supported = await ImageDecoder.isTypeSupported("image/avif");
          console.error(`${tag} imageDecoderSupported=${supported}`);
        } catch (error) {
          console.error(`${tag} imageDecoder=failure message=${String(error && error.message || error)}`);
        }
      } else {
        console.error(`${tag} imageDecoder=unavailable`);
      }
    } catch (error) {
      console.error(`${tag} probe=failure message=${String(error && error.message || error)}`);
    }
  }

  probe();
})();
