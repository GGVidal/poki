// Copied from nab138/iloader src/ErrorContext.tsx at commit 96ed06124d7a859692a5ec2864e1b47998d4904c
// Repository: https://github.com/nab138/iloader
// License: MIT (Copyright (c) 2025 nab138). Full text in third_party/LICENSE.iloader.
// Interface adaptation: Rendered inline inside Poki Setup's Setup screen card instead of a global modal,
// reads locales/en.json and locales/zh_cn.json through useLang(), uses @tauri-apps/plugin-clipboard-manager,
// and links support issues to https://github.com/JosssphZhou/poki/issues.

import React, { useMemo, useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import "./ErrorCard.css";
import {
  type AppError,
  type TFunction,
  getErrorSuggestions,
  mapFailureToErrorVariant,
  parseLinkToken,
} from "./errors";
import enLocale from "./locales/en.json";
import zhLocale from "./locales/zh_cn.json";
import { useLang } from "./i18n";
import { Capsule } from "./ui";

function lookupNested(obj: Record<string, unknown>, path: string): unknown {
  let current: unknown = obj;
  for (const part of path.split(".")) {
    if (!current || typeof current !== "object" || !(part in (current as Record<string, unknown>))) {
      return undefined;
    }
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}

function makeTranslator(lang: "en" | "zh-Hans"): TFunction {
  const primary = (lang === "zh-Hans" ? zhLocale : enLocale) as Record<string, unknown>;
  const fallback = enLocale as Record<string, unknown>;
  return (key, options) => {
    const raw = lookupNested(primary, key) ?? lookupNested(fallback, key) ?? options?.defaultValue ?? key;
    if (options?.returnObjects) {
      if (Array.isArray(raw)) {
        return raw.map((item) =>
          typeof item === "string" && options.anisetteServerUrl
            ? item.replace(/\{\{anisetteServerUrl\}\}/g, options.anisetteServerUrl)
            : item,
        );
      }
      return raw;
    }
    if (typeof raw === "string") {
      let out = raw;
      if (options?.msg !== undefined) out = out.replace(/\{\{msg\}\}/g, options.msg);
      if (options?.anisetteServerUrl !== undefined) {
        out = out.replace(/\{\{anisetteServerUrl\}\}/g, options.anisetteServerUrl);
      }
      return out;
    }
    return String(raw);
  };
}

export function normalizePlatform(os?: string | null): "mac" | "windows" | "linux" {
  const lower = (os ?? "").toLowerCase();
  if (lower.includes("win")) return "windows";
  if (lower.includes("mac") || lower.includes("darwin")) return "mac";
  return "linux";
}

export const ErrorCard: React.FC<{
  title?: string;
  kind: string;
  message: string;
  platform: "mac" | "windows" | "linux";
  anisetteServer?: string;
  onDismiss?: () => void;
}> = ({
  title,
  kind,
  message,
  platform,
  anisetteServer = "https://ani.sidestore.io",
  onDismiss,
}) => {
  const lang = useLang();
  const t = useMemo(() => makeTranslator(lang), [lang]);
  const [moreDetailsOpen, setMoreDetailsOpen] = useState<boolean>(false);
  const [copied, setCopied] = useState<boolean>(false);

  const error: AppError = useMemo(
    () => ({
      type: mapFailureToErrorVariant(kind, message),
      message,
    }),
    [kind, message],
  );

  const suggestions = useMemo(
    () => getErrorSuggestions(t, error.type, platform, anisetteServer),
    [t, error.type, platform, anisetteServer],
  );

  const simpleError = useMemo(() => {
    const lines = error.message.split("\n").filter((line) => line.includes("●"));
    return lines.length > 0 ? lines[lines.length - 1].replace(/●\s*/, "").trim() : null;
  }, [error.message]);

  const copyError = async () => {
    const text = "```\n" + (error.message.replace(/^\n+/, "") || String(t("common.no_error"))) + "\n```";
    try {
      const { writeText } = await import("@tauri-apps/plugin-clipboard-manager");
      await writeText(text);
    } catch {
      await navigator.clipboard?.writeText(text).catch(() => {});
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="error-outer" data-testid={`error-card-${error.type}`}>
      <div className="error-header">
        <h2>{String(t("error.title", { msg: title ?? String(t("error.unknown")) }))}</h2>
        <Capsule kind="ghost" sm onClick={copyError}>
          {copied ? String(t("common.copied_success")) : String(t("common.copy_to_clipboard"))}
        </Capsule>
      </div>
      {simpleError && <pre className="error-inner">{simpleError}</pre>}
      {simpleError && (
        <p
          className="error-more-details"
          role="button"
          tabIndex={0}
          onClick={() => setMoreDetailsOpen(!moreDetailsOpen)}
        >
          {String(t("common.more_details"))} {moreDetailsOpen ? "▲" : "▼"}
        </p>
      )}
      {simpleError && !moreDetailsOpen && (
        <pre className="error-inner error-details-measure">
          {error.message.replace(/^\n+/, "")}
        </pre>
      )}
      {(moreDetailsOpen || !simpleError) && (
        <pre className={`error-inner${simpleError ? " error-details" : ""}`}>
          {error.message.replace(/^\n+/, "")}
        </pre>
      )}
      <div className="suggestions">
        {suggestions.length > 0 && <h3>{String(t("error.suggestions_heading"))}</h3>}
        {suggestions.length > 0 && (
          <ul>
            {suggestions.map((s) => (
              <li key={s}>
                {s
                  .split(/(\(\(link::[^)]+\)\)|\(\(link:[^)]+\)\))/g)
                  .map((part, index) => {
                    const parsed = parseLinkToken(part);
                    if (parsed) {
                      const { url, text } = parsed;
                      return (
                        <a
                          key={index}
                          href={url}
                          onClick={(ev) => {
                            ev.preventDefault();
                            openUrl(url).catch(() => window.open(url, "_blank", "noopener"));
                          }}
                          className="error-link"
                        >
                          {text}
                        </a>
                      );
                    }
                    return <span key={index}>{part}</span>;
                  })}
              </li>
            ))}
          </ul>
        )}
        {error.type !== "underage" && (
          <p className="muted small">
            {lang === "zh-Hans" ? (
              <>
                如果问题仍然存在，请点击「复制到剪贴板」，并前往{" "}
                <a
                  href="https://github.com/JosssphZhou/poki/issues"
                  onClick={(ev) => {
                    ev.preventDefault();
                    openUrl("https://github.com/JosssphZhou/poki/issues").catch(() => {});
                  }}
                  className="error-link"
                >
                  GitHub Issues
                </a>{" "}
                反馈问题。
              </>
            ) : (
              <>
                If the issue persists, press "Copy to clipboard" and open a{" "}
                <a
                  href="https://github.com/JosssphZhou/poki/issues"
                  onClick={(ev) => {
                    ev.preventDefault();
                    openUrl("https://github.com/JosssphZhou/poki/issues").catch(() => {});
                  }}
                  className="error-link"
                >
                  GitHub issue
                </a>{" "}
                for support.
              </>
            )}
          </p>
        )}
      </div>
      {onDismiss && (
        <div>
          <Capsule kind="ghost" sm onClick={onDismiss}>
            {String(t("common.dismiss"))}
          </Capsule>
        </div>
      )}
    </div>
  );
};
