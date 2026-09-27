// Keyboard layouts for the on-screen keyboard. Each layout is a list of rows;
// special keys are written as {k: "<name>"} objects, the rest are plain strings.
// "shift" upper-cases letters; the "sym" layer replaces letters entirely.
globalThis.TOUCHKIT_LAYOUTS = {
  en: {
    label: "EN",
    rows: [
      ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
      ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
      [{ k: "shift" }, "z", "x", "c", "v", "b", "n", "m", { k: "bksp" }],
    ],
  },
  ru: {
    label: "RU",
    rows: [
      ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
      ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
      [{ k: "shift" }, "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", { k: "bksp" }],
    ],
  },
  fr: {
    label: "FR",
    rows: [
      ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
      ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
      [{ k: "shift" }, "w", "x", "c", "v", "b", "n", "é", "è", { k: "bksp" }],
      ["à", "ç", "ê", "ù", "â", "î", "ô", "ë", "ï", "œ"],
    ],
  },
  de: {
    label: "DE",
    rows: [
      ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
      ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
      [{ k: "shift" }, "y", "x", "c", "v", "b", "n", "m", "ß", { k: "bksp" }],
    ],
  },
  sym: {
    label: "123",
    rows: [
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
      ["@", "#", "&", "_", "-", "+", "(", ")", "/", ":"],
      ["*", "\"", "'", ";", "!", "?", "=", "%", "~", { k: "bksp" }],
      ["[", "]", "{", "}", "<", ">", "|", "\\", "$", "€"],
    ],
  },
};
// Bottom row, shared by all layouts.
globalThis.TOUCHKIT_BOTTOM_ROW = [
  { k: "sym" }, { k: "lang" }, ",", { k: "space" }, ".", { k: "enter" }, { k: "hide" },
];
