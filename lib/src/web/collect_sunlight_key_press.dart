const gardendlessCollectSunlightKeyPressScript = r'''
(function () {
  const eventInit = {
    key: "a",
    code: "KeyA",
    keyCode: 65,
    which: 65,
    bubbles: true,
    cancelable: true,
    composed: true
  };
  const target = document.getElementById("GameCanvas") ||
    document.activeElement ||
    document;

  target.dispatchEvent(new KeyboardEvent("keydown", eventInit));
  setTimeout(function () {
    target.dispatchEvent(new KeyboardEvent("keyup", eventInit));
  }, 30);
})();
''';
