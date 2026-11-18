// Copied from nab138/iloader src/errors.tsx at commit 96ed06124d7a859692a5ec2864e1b47998d4904c
// Repository: https://github.com/nab138/iloader
// License: MIT (Copyright (c) 2025 nab138). Full text in third_party/LICENSE.iloader.
// Interface adaptation: TFunction is typed against Poki Setup's JSON locale lookup instead of i18next,
// and mapFailureToErrorVariant maps Poki Setup's core error kinds to ErrorVariant.

export type TFunction = (
  key: string,
  options?: {
    returnObjects?: boolean;
    defaultValue?: unknown;
    anisetteServerUrl?: string;
    msg?: string;
  },
) => unknown;

export const errorSuggestionKeys = {
  underage: ["error.suggestions.underage"],
  account_locked: ["error.suggestions.account_locked"],
  developer: [],
  auth: ["error.suggestions.auth"],
  download: ["error.suggestions.download"],
  house_arrest: [
    "error.suggestions.house_arrest",
    "error.suggestions.trust",
    "error.suggestions.device_coms",
  ],
  remote_pairing: ["error.suggestions.trust", "error.suggestions.pairing"],
  lockdown_pairing: ["error.suggestions.trust", "error.suggestions.pairing"],
  canceled: [],
  operation_update: [],
  device_coms: ["error.suggestions.device_coms", "error.suggestions.trust"],
  device_coms_with_message: [
    "error.suggestions.device_coms",
    "error.suggestions.trust",
  ],
  usbmuxd: [
    "error.suggestions.usbmuxd",
    "error.suggestions.device_coms",
    "error.suggestions.trust",
  ],
  not_logged_in: ["error.suggestions.not_logged_in"],
  no_device_selected: ["error.suggestions.no_device_selected"],
  anisette: ["error.suggestions.anisette"],
  keyring: ["error.suggestions.keyring", "error.suggestions.admin"],
  keyring_with_message: [
    "error.suggestions.keyring",
    "error.suggestions.admin",
  ],
  storage: [
    "error.suggestions.keyring",
    "error.suggestions.admin",
    "error.suggestions.filesystem",
  ],
  misc: ["error.suggestions.misc"],
  filesystem: ["error.suggestions.filesystem", "error.suggestions.admin"],
  not_enough_app_ids: ["error.suggestions.not_enough_app_ids"],
  max_apps: ["error.suggestions.max_apps"],
} as const;

export type ErrorVariant = keyof typeof errorSuggestionKeys;

export type AppError = {
  type: ErrorVariant;
  message: string;
};

export const isErrorVariant = (value: string): value is ErrorVariant => {
  return value in errorSuggestionKeys;
};

const normalizeAnisetteServer = (anisetteServer: string) => {
  return anisetteServer.startsWith("http://") ||
    anisetteServer.startsWith("https://")
    ? anisetteServer
    : `https://${anisetteServer}`;
};

const dedupeSuggestions = (suggestions: string[]) => {
  return [...new Set(suggestions)];
};

const getSuggestionBlock = (
  t: TFunction,
  key: string,
  platform: "mac" | "windows" | "linux",
  anisetteServer: string,
) => {
  const rawSuggestions = t(key, {
    returnObjects: true,
    defaultValue: [],
    anisetteServerUrl: normalizeAnisetteServer(anisetteServer),
  }) as unknown;

  if (!Array.isArray(rawSuggestions)) {
    return [];
  }

  return rawSuggestions
    .filter((suggestion): suggestion is string => {
      if (typeof suggestion !== "string") {
        return false;
      }
      if (suggestion.startsWith("[platform::")) {
        const platformEnd = suggestion.indexOf("]");
        if (platformEnd !== -1) {
          const suggestionPlatform = suggestion.substring(11, platformEnd);
          if (suggestionPlatform === platform) {
            return true;
          }
        }
        return false;
      }
      return true;
    })
    .map((s) =>
      s
        .replace(/^\[platform::.*?\]/, "")
        .replace(/\[ios::.*?\]/g, "")
        .trim(),
    );
};

export const getErrorSuggestions = (
  t: TFunction,
  type: ErrorVariant,
  platform: "mac" | "windows" | "linux",
  anisetteServer: string,
): string[] => {
  return dedupeSuggestions(
    errorSuggestionKeys[type].flatMap((key) =>
      getSuggestionBlock(t, key, platform, anisetteServer),
    ),
  );
};

export const parseLinkToken = (
  token: string,
): { url: string; text: string } | null => {
  const doubleColonMatch = token.match(/^\(\(link::([^)]+)\)\)$/);
  if (doubleColonMatch) {
    const url = doubleColonMatch[1].trim();
    return url ? { url, text: url } : null;
  }

  const singleColonMatch = token.match(/^\(\(link:([^)]+)\)\)$/);
  if (!singleColonMatch) {
    return null;
  }

  const payload = singleColonMatch[1].trim();
  if (!payload) {
    return null;
  }

  const lastColon = payload.lastIndexOf(":");
  if (lastColon > 0) {
    const possibleUrl = payload.slice(0, lastColon).trim();
    const possibleText = payload.slice(lastColon + 1).trim();
    if (possibleText && /^[a-z][a-z0-9+.-]*:\/\//i.test(possibleUrl)) {
      return { url: possibleUrl, text: possibleText };
    }
  }

  return { url: payload, text: payload };
};

export const mapFailureToErrorVariant = (
  kind: string,
  message: string,
): ErrorVariant => {
  if (isErrorVariant(kind)) {
    return kind;
  }
  const lower = message.toLowerCase();
  if (kind === "usbmuxd" || lower.includes("usbmuxd") || lower.includes("iphone service")) {
    return "usbmuxd";
  }
  if (kind === "not_enough_app_ids" || lower.includes("available app ids")) {
    return "not_enough_app_ids";
  }
  if (lower.includes("three apps at a time") || lower.includes("3 apps")) {
    return "max_apps";
  }
  if (kind === "keychain") {
    return "keyring";
  }
  if (kind === "apple") {
    if (lower.includes("locked") || lower.includes("iforgot")) return "account_locked";
    if (lower.includes("anisette")) return "anisette";
    return "auth";
  }
  if (kind === "needs_person") {
    if (lower.includes("trust") || lower.includes("pair")) return "lockdown_pairing";
    return "device_coms";
  }
  if (kind === "http") {
    return "download";
  }
  if (kind === "io") {
    return "filesystem";
  }
  if (kind === "device") {
    if (lower.includes("container") || lower.includes("house")) return "house_arrest";
    if (lower.includes("pair") || lower.includes("trust")) return "lockdown_pairing";
    return "device_coms";
  }
  return "misc";
};
