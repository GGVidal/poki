// Real YAML parser and GitHub Actions expression evaluator for workflow contract tests.
import { execFileSync } from 'node:child_process';

const PY_YAML_TO_JSON = `
import json, sys, yaml

def normalize(value):
    if isinstance(value, dict):
        return {("on" if k is True else str(k)): normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    return value

print(json.dumps(normalize(yaml.safe_load(sys.stdin.read()))))
`;

const RUBY_YAML_TO_JSON = `
require "yaml"
require "json"

def normalize(value)
  case value
  when Hash
    value.each_with_object({}) { |(k, v), out| out[k == true ? "on" : k.to_s] = normalize(v) }
  when Array
    value.map { |item| normalize(item) }
  else
    value
  end
end

puts JSON.generate(normalize(YAML.safe_load($stdin.read)))
`;

export function parseWorkflowYaml(text) {
  try {
    const out = execFileSync('python3', ['-B', '-c', PY_YAML_TO_JSON], {
      input: text,
      encoding: 'utf8',
    });
    return JSON.parse(out);
  } catch {
    const out = execFileSync('ruby', ['-e', RUBY_YAML_TO_JSON], {
      input: text,
      encoding: 'utf8',
    });
    return JSON.parse(out);
  }
}

export function actionsTruthy(value) {
  return !(value === false || value === 0 || value === '' || value === null || value === undefined || Number.isNaN(value));
}

function toActionsNumber(value) {
  if (value === null || value === undefined || value === false) return 0;
  if (value === true) return 1;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') return 0;
    return Number(trimmed);
  }
  return NaN;
}

// GitHub Actions equality ignores case on strings and coerces mismatched types to numbers:
// https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#operators
export function actionsEqual(left, right) {
  const a = left === undefined ? null : left;
  const b = right === undefined ? null : right;
  if (typeof a === 'string' && typeof b === 'string') {
    return a.toLowerCase() === b.toLowerCase();
  }
  if (typeof a === typeof b) {
    return a === b;
  }
  const na = toActionsNumber(a);
  const nb = toActionsNumber(b);
  return !Number.isNaN(na) && !Number.isNaN(nb) && na === nb;
}

function tokenize(expr) {
  const tokens = [];
  let i = 0;
  while (i < expr.length) {
    if (/\s/.test(expr[i])) {
      i++;
      continue;
    }
    const two = expr.slice(i, i + 2);
    if (['==', '!=', '&&', '||', '<=', '>='].includes(two)) {
      tokens.push({ t: two });
      i += 2;
      continue;
    }
    if (['(', ')', '!', ',', '.', '<', '>'].includes(expr[i])) {
      tokens.push({ t: expr[i] });
      i++;
      continue;
    }
    if (expr[i] === "'") {
      let s = '';
      i++;
      while (i < expr.length) {
        if (expr[i] === "'" && expr[i + 1] === "'") {
          s += "'";
          i += 2;
          continue;
        }
        if (expr[i] === "'") {
          i++;
          break;
        }
        s += expr[i++];
      }
      tokens.push({ t: 'str', v: s });
      continue;
    }
    const num = expr.slice(i).match(/^-?\d+(?:\.\d+)?/);
    if (num) {
      tokens.push({ t: 'num', v: Number(num[0]) });
      i += num[0].length;
      continue;
    }
    const ident = expr.slice(i).match(/^[A-Za-z_][A-Za-z0-9_-]*/);
    if (ident) {
      tokens.push({ t: 'id', v: ident[0] });
      i += ident[0].length;
      continue;
    }
    throw new Error(`Unsupported Actions expression near: ${expr.slice(i)}`);
  }
  return tokens;
}

function lookupPath(ctx, parts) {
  const joined = parts.join('.');
  if (Object.hasOwn(ctx, joined)) return ctx[joined];
  let cur = ctx;
  for (const part of parts) {
    if (cur == null || typeof cur !== 'object') return null;
    if (Object.hasOwn(cur, part)) {
      cur = cur[part];
      continue;
    }
    const match = Object.keys(cur).find(k => k.toLowerCase() === part.toLowerCase());
    if (match === undefined) return null;
    cur = cur[match];
  }
  return cur;
}

export function evalActionsExpr(expr, ctx = {}) {
  const tokens = tokenize(expr);
  let pos = 0;
  const peek = () => tokens[pos];
  const take = () => tokens[pos++];

  function parseOr() {
    let left = parseAnd();
    while (peek()?.t === '||') {
      take();
      const right = parseAnd();
      left = actionsTruthy(left) ? left : right;
    }
    return left;
  }

  function parseAnd() {
    let left = parseEq();
    while (peek()?.t === '&&') {
      take();
      const right = parseEq();
      left = actionsTruthy(left) ? right : left;
    }
    return left;
  }

  function parseEq() {
    let left = parseUnary();
    while (peek()?.t === '==' || peek()?.t === '!=') {
      const op = take().t;
      const right = parseUnary();
      left = op === '==' ? actionsEqual(left, right) : !actionsEqual(left, right);
    }
    return left;
  }

  function parseUnary() {
    if (peek()?.t === '!') {
      take();
      return !actionsTruthy(parseUnary());
    }
    return parsePostfix();
  }

  function callFunction(name, args) {
    const fn = name.toLowerCase();
    if (fn === 'always') return true;
    if (fn === 'cancelled') return Boolean(ctx.__cancelled);
    if (fn === 'success') return ctx.__success !== undefined ? Boolean(ctx.__success) : !ctx.__cancelled;
    if (fn === 'failure') return Boolean(ctx.__failure);
    if (fn === 'fromjson') {
      const raw = args[0];
      return raw ? JSON.parse(String(raw)) : null;
    }
    if (fn === 'format') {
      const [template, ...rest] = args;
      return String(template ?? '').replace(/\{(\d+)\}/g, (_, idx) => String(rest[Number(idx)] ?? ''));
    }
    if (fn === 'contains') {
      const [haystack, needle] = args;
      if (Array.isArray(haystack)) return haystack.some(item => actionsEqual(item, needle));
      return String(haystack ?? '').toLowerCase().includes(String(needle ?? '').toLowerCase());
    }
    if (fn === 'startswith') {
      return String(args[0] ?? '').toLowerCase().startsWith(String(args[1] ?? '').toLowerCase());
    }
    if (fn === 'endswith') {
      return String(args[0] ?? '').toLowerCase().endsWith(String(args[1] ?? '').toLowerCase());
    }
    throw new Error(`Unsupported Actions function: ${name}`);
  }

  function parsePostfix() {
    let value;
    const tok = take();
    if (!tok) throw new Error(`Unexpected end of expression: ${expr}`);
    if (tok.t === '(') {
      value = parseOr();
      if (take()?.t !== ')') throw new Error(`Unclosed '(' in: ${expr}`);
    } else if (tok.t === 'str' || tok.t === 'num') {
      value = tok.v;
    } else if (tok.t === 'id') {
      if (peek()?.t === '(') {
        take();
        const args = [];
        if (peek()?.t !== ')') {
          args.push(parseOr());
          while (peek()?.t === ',') {
            take();
            args.push(parseOr());
          }
        }
        if (take()?.t !== ')') throw new Error(`Unclosed call ${tok.v}() in: ${expr}`);
        value = callFunction(tok.v, args);
      } else {
        const parts = [tok.v];
        while (peek()?.t === '.') {
          take();
          const next = take();
          if (next?.t !== 'id') throw new Error(`Expected property name after '.' in: ${expr}`);
          parts.push(next.v);
        }
        if (parts.length === 1) {
          const lower = parts[0].toLowerCase();
          if (lower === 'true') value = true;
          else if (lower === 'false') value = false;
          else if (lower === 'null') value = null;
          else value = lookupPath(ctx, parts);
        } else {
          value = lookupPath(ctx, parts);
        }
      }
    } else {
      throw new Error(`Unexpected token ${tok.t} in: ${expr}`);
    }

    while (peek()?.t === '.') {
      take();
      const prop = take();
      if (prop?.t !== 'id') throw new Error(`Expected property name after '.' in: ${expr}`);
      if (value != null && typeof value === 'object') {
        const key = Object.hasOwn(value, prop.v)
          ? prop.v
          : Object.keys(value).find(k => k.toLowerCase() === prop.v.toLowerCase());
        value = key === undefined ? null : value[key];
      } else {
        value = null;
      }
    }
    return value;
  }

  const result = parseOr();
  if (pos !== tokens.length) {
    throw new Error(`Unparsed trailing tokens in: ${expr}`);
  }
  return result;
}

export function evalActionsField(raw, ctx = {}) {
  if (raw === null || raw === undefined) return '';
  if (typeof raw !== 'string') return raw;
  const full = raw.trim().match(/^\$\{\{\s*([\s\S]*?)\s*\}\}$/);
  if (full && !full[1].includes('${{')) {
    const val = evalActionsExpr(full[1], ctx);
    return val === null || val === undefined ? '' : val;
  }
  return raw.replace(/\$\{\{\s*([\s\S]*?)\s*\}\}/g, (_, inner) => {
    const val = evalActionsExpr(inner, ctx);
    return val === null || val === undefined ? '' : String(val);
  });
}

export function jobNeeds(job) {
  if (!job?.needs) return [];
  return Array.isArray(job.needs) ? job.needs.map(String) : [String(job.needs)];
}

export function evalJobIf(job, ctx = {}) {
  const cancelled = Boolean(ctx.__cancelled);
  const needsResults = jobNeeds(job).map(id => ctx[`needs.${id}.result`] ?? ctx.needs?.[id]?.result ?? 'success');
  const defaultSuccess = !cancelled && needsResults.every(r => r === 'success');
  if (job?.if === undefined || job?.if === null) {
    return defaultSuccess;
  }
  if (typeof job.if === 'boolean') {
    return defaultSuccess && job.if;
  }
  const stripped = String(job.if).trim().replace(/^\$\{\{\s*|\s*\}\}$/g, '');
  const hasStatusFn = /\b(?:always|failure|cancelled|success)\s*\(/i.test(stripped);
  const evalCtx = { ...ctx, __cancelled: cancelled, __success: defaultSuccess };
  const result = actionsTruthy(evalActionsExpr(stripped, evalCtx));
  return hasStatusFn ? result : (defaultSuccess && result);
}

export function jobEnvironment(job, ctx = {}) {
  const env = job?.environment;
  if (!env) return '';
  const raw = typeof env === 'string' ? env : env.name;
  return raw == null ? '' : String(evalActionsField(raw, ctx));
}
