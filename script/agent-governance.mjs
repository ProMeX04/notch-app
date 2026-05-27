#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url))
const DEFAULT_ROOT = path.resolve(SCRIPT_DIR, '..')
const SKILL_MIRRORS = ['.codex/skills', '.claude/skills', '.agents/skills']
const RULE_MIRRORS = {
  claude: '.claude/rules',
  antigravity: '.agents/rules',
}

function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

function ensureParent(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
}

function writeExact(file, content) {
  ensureParent(file)
  fs.writeFileSync(file, content)
}

function readIfPresent(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
}

function relative(root, file) {
  return path.relative(root, file).split(path.sep).join('/')
}

function walk(directory) {
  if (!fs.existsSync(directory)) return []
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const child = path.join(directory, entry.name)
    return entry.isDirectory() ? walk(child) : [child]
  })
}

function openAIYAML(skill) {
  return [
    'interface:',
    `  display_name: ${JSON.stringify(skill.displayName)}`,
    `  short_description: ${JSON.stringify(skill.shortDescription)}`,
    `  default_prompt: ${JSON.stringify(skill.defaultPrompt)}`,
    '',
  ].join('\n')
}

function governance(root) {
  const source = path.join(root, '.agent-governance')
  return {
    source,
    manifest: readJSON(path.join(source, 'manifest.json')),
    baseline: readJSON(path.join(source, 'baseline.json')),
  }
}

export function syncGovernance(root = DEFAULT_ROOT) {
  const { source, manifest } = governance(root)

  for (const skill of manifest.skills) {
    const skillSource = fs.readFileSync(
      path.join(source, 'skills', skill.name, 'SKILL.md'),
      'utf8',
    )
    for (const mirror of SKILL_MIRRORS) {
      writeExact(path.join(root, mirror, skill.name, 'SKILL.md'), skillSource)
    }
    writeExact(
      path.join(root, '.codex/skills', skill.name, 'agents/openai.yaml'),
      openAIYAML(skill),
    )
  }

  for (const [provider, files] of Object.entries(manifest.rules)) {
    for (const file of files) {
      const content = fs.readFileSync(
        path.join(source, 'rules', provider, file),
        'utf8',
      )
      writeExact(path.join(root, RULE_MIRRORS[provider], file), content)
    }
  }

  const staleRule = path.join(root, '.agents/rules/notch-api-conventions.md')
  if (fs.existsSync(staleRule)) fs.rmSync(staleRule)
}

function compareGenerated(errors, expected, actualFile, label) {
  const actual = readIfPresent(actualFile)
  if (actual === null) {
    errors.push(`Missing generated ${label}: ${actualFile}`)
  } else if (actual !== expected) {
    errors.push(`Generated ${label} is stale or edited directly: ${actualFile}`)
  }
}

function checkUnregisteredNativeOutputs(errors, root, manifest) {
  const skills = new Set(manifest.skills.map((skill) => skill.name))
  for (const mirror of SKILL_MIRRORS) {
    const directory = path.join(root, mirror)
    if (!fs.existsSync(directory)) continue
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (
        entry.isDirectory() &&
        entry.name.startsWith('notch-') &&
        !skills.has(entry.name)
      ) {
        errors.push(`Unregistered native Notch skill outside canonical manifest: ${mirror}/${entry.name}`)
      }
    }
  }

  for (const [provider, mirror] of Object.entries(RULE_MIRRORS)) {
    const expected = new Set(manifest.rules[provider] ?? [])
    const directory = path.join(root, mirror)
    if (!fs.existsSync(directory)) continue
    for (const file of fs.readdirSync(directory)) {
      if (file.endsWith('.md') && !expected.has(file)) {
        errors.push(`Unregistered native ${provider} rule outside canonical manifest: ${mirror}/${file}`)
      }
    }
  }
}

function checkBacktickReferences(errors, root, file, base = root) {
  const content = readIfPresent(file)
  if (content === null) return
  const references =
    /`((?:\.\.\/)?(?:docs|Sources|Tests|script|portal)\/[^`\s]+\.(?:md|swift|mjs|ts))`/g
  for (const match of content.matchAll(references)) {
    if (!fs.existsSync(path.resolve(base, match[1]))) {
      errors.push(
        `Broken governance reference in ${relative(root, file)}: ${match[1]}`,
      )
    }
  }
}

function countLineMatches(root, files, expression) {
  const findings = new Map()
  for (const file of files) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/)
    let count = 0
    for (const line of lines) {
      if (expression.test(line)) count += 1
      expression.lastIndex = 0
    }
    if (count > 0) findings.set(relative(root, file), count)
  }
  return findings
}

function checkRuleCounts(errors, rule, findings, baseline) {
  const accepted = baseline[rule] ?? {}
  for (const [file, count] of findings) {
    const maximum = accepted[file]?.maxMatches ?? 0
    if (count > maximum) {
      errors.push(
        `${rule} violation increased in ${file}: found ${count}, baseline permits ${maximum}`,
      )
    }
  }
}

function architectureErrors(root, baseline) {
  const errors = []
  const sourceFiles = walk(path.join(root, 'Sources')).filter((file) => {
    const rel = relative(root, file)
    return /^Sources\/[^/]+Core\/.*\.swift$/.test(rel)
  })
  const focusRouteFiles = walk(path.join(root, 'portal/src/app/api/focus')).filter(
    (file) => file.endsWith('.ts'),
  )
  const focusLib = [path.join(root, 'portal/src/lib/focus-ranking.ts')].filter(
    (file) => fs.existsSync(file),
  )
  const swiftFiles = walk(path.join(root, 'Sources')).filter((file) =>
    file.endsWith('.swift'),
  )
  const runtimeFiles = [
    ...walk(path.join(root, 'Sources')),
    ...walk(path.join(root, 'portal/src')),
  ].filter((file) => {
    const rel = relative(root, file)
    return (
      /\.(swift|ts|tsx|js|jsx)$/.test(file) &&
      !rel.includes('/Resources/') &&
      !rel.includes('/Tests/')
    )
  })

  checkRuleCounts(
    errors,
    'core-infrastructure',
    countLineMatches(
      root,
      sourceFiles,
      /\b(?:URLSession|URLRequest|HTTPURLResponse|KeychainHelper|SecItem|accessToken|refreshToken)\b/,
    ),
    baseline,
  )
  checkRuleCounts(
    errors,
    'core-userdefaults',
    countLineMatches(root, sourceFiles, /\bUserDefaults\b/),
    baseline,
  )
  checkRuleCounts(
    errors,
    'swift-sync-userdefaults',
    countLineMatches(
      root,
      swiftFiles,
      /(?:sync|Sync|outbox|Outbox|pending|Pending|cloud|Cloud).*\bUserDefaults\b|\bUserDefaults\b.*(?:sync|Sync|outbox|Outbox|pending|Pending|cloud|Cloud)/,
    ),
    baseline,
  )
  checkRuleCounts(
    errors,
    'focus-client-ownership',
    countLineMatches(
      root,
      focusRouteFiles,
      /\bbody\??\.(?:user_id|device_id|userId|deviceId)\b/,
    ),
    baseline,
  )
  checkRuleCounts(
    errors,
    'leaderboard-private-name',
    countLineMatches(root, focusLib, /\buser\.name\b/),
    baseline,
  )
  checkRuleCounts(
    errors,
    'development-data-compatibility',
    countLineMatches(
      root,
      runtimeFiles,
      /\b(?:legacy|migrat(?:e|ed|es|ing|ion)|backward compatibility|backwards compatibility|compatibility branch|old-client|older-client|older clients?|previous version|fallback(?:AddedAt|Date|Path))\b/i,
    ),
    baseline,
  )
  return errors
}

function baselineErrors(baseline) {
  const errors = []
  if (baseline.mode !== 'zero-debt') {
    errors.push('Governance baseline must use mode "zero-debt" during development')
  }
  for (const [rule, allowances] of Object.entries(baseline.rules ?? {})) {
    for (const [file, allowance] of Object.entries(allowances)) {
      errors.push(`Governance baseline allowances are forbidden during development: ${rule} in ${file}`)
      if (
        !Number.isInteger(allowance.maxMatches) ||
        allowance.maxMatches < 1 ||
        typeof allowance.reason !== 'string' ||
        allowance.reason.trim().length === 0
      ) {
        errors.push(`Invalid governance baseline allowance: ${rule} in ${file}`)
      }
    }
  }
  return errors
}

export function checkGovernance(root = DEFAULT_ROOT) {
  const { source, manifest, baseline } = governance(root)
  const errors = []

  for (const required of manifest.requiredFiles) {
    if (!fs.existsSync(path.join(root, required))) {
      errors.push(`Missing required governance entrypoint or standard: ${required}`)
    }
  }

  checkUnregisteredNativeOutputs(errors, root, manifest)

  for (const skill of manifest.skills) {
    const sourceFile = path.join(source, 'skills', skill.name, 'SKILL.md')
    const expected = readIfPresent(sourceFile)
    if (expected === null) {
      errors.push(`Missing canonical skill: ${relative(root, sourceFile)}`)
      continue
    }
    if (
      !expected.includes(`name: ${skill.name}`) ||
      !expected.includes('description:')
    ) {
      errors.push(`Invalid canonical skill frontmatter: ${relative(root, sourceFile)}`)
    }
    checkBacktickReferences(errors, root, sourceFile)
    for (const mirror of SKILL_MIRRORS) {
      compareGenerated(
        errors,
        expected,
        path.join(root, mirror, skill.name, 'SKILL.md'),
        `skill ${skill.name}`,
      )
    }
    compareGenerated(
      errors,
      openAIYAML(skill),
      path.join(root, '.codex/skills', skill.name, 'agents/openai.yaml'),
      `Codex skill metadata ${skill.name}`,
    )
  }

  for (const [provider, files] of Object.entries(manifest.rules)) {
    for (const file of files) {
      const sourceFile = path.join(source, 'rules', provider, file)
      const expected = readIfPresent(sourceFile)
      if (expected === null) {
        errors.push(`Missing canonical ${provider} rule: ${relative(root, sourceFile)}`)
        continue
      }
      checkBacktickReferences(errors, root, sourceFile)
      compareGenerated(
        errors,
        expected,
        path.join(root, RULE_MIRRORS[provider], file),
        `${provider} rule ${file}`,
      )
    }
  }

  checkBacktickReferences(errors, root, path.join(root, 'AGENTS.md'))
  checkBacktickReferences(errors, root, path.join(root, 'portal/AGENTS.md'), path.join(root, 'portal'))
  checkBacktickReferences(errors, root, path.join(root, 'Sources/AGENTS.md'), path.join(root, 'Sources'))
  checkBacktickReferences(errors, root, path.join(root, 'Tests/AGENTS.md'), path.join(root, 'Tests'))

  if (fs.existsSync(path.join(root, '.agents/rules/notch-api-conventions.md'))) {
    errors.push('Stale Antigravity rule must be replaced by generated scoped rules')
  }

  const claude = readIfPresent(path.join(root, 'CLAUDE.md')) ?? ''
  for (const duplicated of [
    '## Architecture overview',
    '## Swift Architecture Rule',
    '## Required API Skills',
  ]) {
    if (claude.includes(duplicated)) {
      errors.push(`CLAUDE.md duplicates canonical guidance: ${duplicated}`)
    }
  }
  if ((readIfPresent(path.join(root, 'portal/CLAUDE.md')) ?? '').trim() !== '@AGENTS.md') {
    errors.push('portal/CLAUDE.md must remain a direct @AGENTS.md import')
  }

  errors.push(...baselineErrors(baseline))
  errors.push(...architectureErrors(root, baseline.rules ?? {}))
  return errors
}

function main() {
  const mode = process.argv[2]
  if (mode === 'sync') {
    syncGovernance()
    const errors = checkGovernance()
    if (errors.length > 0) {
      console.error(errors.join('\n'))
      process.exitCode = 1
      return
    }
    console.log('Agent governance mirrors synchronized and validated.')
    return
  }
  if (mode === 'check') {
    const errors = checkGovernance()
    if (errors.length > 0) {
      console.error(errors.join('\n'))
      process.exitCode = 1
      return
    }
    console.log('Agent governance validation passed.')
    return
  }
  console.error('Usage: node script/agent-governance.mjs <sync|check>')
  process.exitCode = 1
}

if (path.resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  main()
}
